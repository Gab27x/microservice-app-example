package main

import (
    "errors"
    "net/http"
    "testing"
    "time"
)

type failingClient struct{}

func (f *failingClient) Do(req *http.Request) (*http.Response, error) {
    return nil, errors.New("simulated failure")
}

type okClient struct{}

func (o *okClient) Do(req *http.Request) (*http.Response, error) {
    return &http.Response{StatusCode: 200, Body: http.NoBody}, nil
}

func TestCircuitBreakerOpensAndRecovers(t *testing.T) {
    // Start with a failing client to trigger failures
    failing := &failingClient{}
    cbClient := newBreakerHTTPClient(failing, "test-breaker")

    req, _ := http.NewRequest("GET", "http://example.local", nil)

    // Cause multiple failures
    for i := 0; i < 6; i++ {
        _, err := cbClient.Do(req)
        if err == nil {
            t.Fatalf("expected error from failing client on iteration %d", i)
        }
    }

    // After failures, circuit should be open and return gobreaker.ErrOpenState
    _, err := cbClient.Do(req)
    if err == nil {
        t.Fatalf("expected error due to open circuit")
    }

    // Replace underlying client with a healthy one and wait for timeout to allow half-open
    cbClient.client = &okClient{}
    // Wait longer than Timeout (2s in settings)
    time.Sleep(3 * time.Second)

    // A request now should succeed (half-open then closed)
    resp, err := cbClient.Do(req)
    if err != nil {
        t.Fatalf("expected success after recovery but got error: %v", err)
    }
    if resp.StatusCode != 200 {
        t.Fatalf("expected 200 status code, got %d", resp.StatusCode)
    }
}
