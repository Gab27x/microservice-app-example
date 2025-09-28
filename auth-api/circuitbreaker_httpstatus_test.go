package main

import (
    "net/http"
    "testing"

    "github.com/sony/gobreaker"
)

// client that returns a 500 response
type serverErrorClient struct{}

func (s *serverErrorClient) Do(req *http.Request) (*http.Response, error) {
    return &http.Response{StatusCode: 500, Body: http.NoBody}, nil
}

func TestServerErrorCountsAsFailure(t *testing.T) {
    client := &serverErrorClient{}
    cbClient := newBreakerHTTPClient(client, "test-status-breaker")

    req, _ := http.NewRequest("GET", "http://example.local", nil)

    // cause several 500s to make breaker open
    for i := 0; i < 6; i++ {
        _, err := cbClient.Do(req)
        if err == nil {
            t.Fatalf("expected error on iteration %d", i)
        }
    }

    // After failures, circuit should be open
    state, _ := cbClient.Status()
    if state != gobreaker.StateOpen {
        t.Fatalf("expected breaker to be open, got %s", state.String())
    }
}
