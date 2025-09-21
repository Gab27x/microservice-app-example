package main

import (
    "fmt"
    "net/http"
    "os"
    "strconv"
    "sync/atomic"
    "time"

    "github.com/sony/gobreaker"
)

// breakerHTTPClient wraps an HTTPDoer and uses gobreaker to protect calls.
type breakerHTTPClient struct {
    cb     *gobreaker.CircuitBreaker
    client HTTPDoer
    // simple atomic counters to provide stable metrics for the handler
    reqs uint64
    succ uint64
    fail uint64
    consSucc uint64
    consFail uint64
}

func newBreakerHTTPClient(client HTTPDoer, name string) *breakerHTTPClient {
    // Read configuration from environment with sensible defaults for testing.
    maxRequests := int64(2)
    if v := os.Getenv("CB_MAX_REQUESTS"); v != "" {
        if n, err := strconv.ParseInt(v, 10, 64); err == nil {
            maxRequests = n
        }
    }

    interval := 30 * time.Second
    if v := os.Getenv("CB_INTERVAL_SECONDS"); v != "" {
        if n, err := strconv.Atoi(v); err == nil {
            interval = time.Duration(n) * time.Second
        }
    }

    timeout := 2 * time.Second
    if v := os.Getenv("CB_TIMEOUT_SECONDS"); v != "" {
        if n, err := strconv.Atoi(v); err == nil {
            timeout = time.Duration(n) * time.Second
        }
    }

    minRequests := int64(5)
    if v := os.Getenv("CB_MIN_REQUESTS"); v != "" {
        if n, err := strconv.ParseInt(v, 10, 64); err == nil {
            minRequests = n
        }
    }

    failureRatio := 0.5
    if v := os.Getenv("CB_FAILURE_RATIO"); v != "" {
        if f, err := strconv.ParseFloat(v, 64); err == nil {
            failureRatio = f
        }
    }

    consecutiveFailures := int64(5)
    if v := os.Getenv("CB_CONSECUTIVE_FAILURES"); v != "" {
        if n, err := strconv.ParseInt(v, 10, 64); err == nil {
            consecutiveFailures = n
        }
    }

    settings := gobreaker.Settings{
        Name:        name,
        MaxRequests: uint32(maxRequests), // when half-open allow a couple requests
        Interval:    interval,
        Timeout:     timeout,
        ReadyToTrip: func(counts gobreaker.Counts) bool {
            // open the circuit if minRequests reached and error ratio >= failureRatio
            failures := counts.TotalFailures
            total := counts.Requests
            if total >= uint32(minRequests) && float64(failures)/float64(total) >= failureRatio {
                return true
            }
            if counts.ConsecutiveFailures >= uint32(consecutiveFailures) {
                return true
            }
            return false
        },
    }

    cb := gobreaker.NewCircuitBreaker(settings)
    return &breakerHTTPClient{cb: cb, client: client}
}

func (b *breakerHTTPClient) Do(req *http.Request) (*http.Response, error) {
    // capture context so we can cancel if needed
    ctx := req.Context()
    atomic.AddUint64(&b.reqs, 1)

    // Execute the HTTP call inside the circuit breaker. We adapt to gobreaker's Execute signature.
    result, err := b.cb.Execute(func() (interface{}, error) {
        // Respect context deadlines by using the underlying client's Do directly
        resp, err := b.client.Do(req.WithContext(ctx))
        if err != nil {
            return nil, err
        }
        // Treat 5xx responses as errors so the breaker counts them
        if resp.StatusCode >= 500 {
            // close body to avoid leaks since we are returning an error
            if resp.Body != nil {
                resp.Body.Close()
            }
            return nil, fmt.Errorf("server error: %d", resp.StatusCode)
        }
        return resp, nil
    })

    if err != nil {
        atomic.AddUint64(&b.fail, 1)
        atomic.AddUint64(&b.consFail, 1)
        atomic.StoreUint64(&b.consSucc, 0)
        return nil, err
    }

    // type assert the result
    resp, _ := result.(*http.Response)
    if resp.StatusCode >= 500 {
        atomic.AddUint64(&b.fail, 1)
        atomic.AddUint64(&b.consFail, 1)
        atomic.StoreUint64(&b.consSucc, 0)
        return nil, fmt.Errorf("server error: %d", resp.StatusCode)
    }

    // success
    atomic.AddUint64(&b.succ, 1)
    atomic.AddUint64(&b.consSucc, 1)
    atomic.StoreUint64(&b.consFail, 0)
    return resp, nil
}

// ensure breakerHTTPClient implements HTTPDoer
var _ HTTPDoer = (*breakerHTTPClient)(nil)

// Status returns the current state and counts of the internal circuit breaker.
func (b *breakerHTTPClient) Status() (gobreaker.State, gobreaker.Counts) {
    return b.cb.State(), b.cb.Counts()
}

// LocalCounts returns a stable snapshot of wrapper counters for debugging.
func (b *breakerHTTPClient) LocalCounts() map[string]uint64 {
    return map[string]uint64{
        "Requests":             atomic.LoadUint64(&b.reqs),
        "TotalSuccesses":       atomic.LoadUint64(&b.succ),
        "TotalFailures":        atomic.LoadUint64(&b.fail),
        "ConsecutiveSuccesses": atomic.LoadUint64(&b.consSucc),
        "ConsecutiveFailures":  atomic.LoadUint64(&b.consFail),
    }
}
