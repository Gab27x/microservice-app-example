package main

import (
    "fmt"
    "net/http"
    "time"

    "github.com/sony/gobreaker"
)

// breakerHTTPClient wraps an HTTPDoer and uses gobreaker to protect calls.
type breakerHTTPClient struct {
    cb     *gobreaker.CircuitBreaker
    client HTTPDoer
}

func newBreakerHTTPClient(client HTTPDoer, name string) *breakerHTTPClient {
    settings := gobreaker.Settings{
        Name:        name,
        MaxRequests: 2, // when half-open allow a couple requests
    Interval:    30 * time.Second,
    Timeout:     2 * time.Second,
        ReadyToTrip: func(counts gobreaker.Counts) bool {
            // open the circuit if more than 5 consecutive failures or error ratio > 50%
            failures := counts.TotalFailures
            total := counts.Requests
            if total >= 5 && float64(failures)/float64(total) >= 0.5 {
                return true
            }
            if counts.ConsecutiveFailures >= 5 {
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
        return nil, err
    }

    // type assert the result
    resp, _ := result.(*http.Response)
    return resp, nil
}

// ensure breakerHTTPClient implements HTTPDoer
var _ HTTPDoer = (*breakerHTTPClient)(nil)

// Status returns the current state and counts of the internal circuit breaker.
func (b *breakerHTTPClient) Status() (gobreaker.State, gobreaker.Counts) {
    return b.cb.State(), b.cb.Counts()
}
