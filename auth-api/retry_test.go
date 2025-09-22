package main

import (
    "errors"
    "net/http"
    "testing"
    "time"
)

// fakeClient allows scripting a sequence of responses/errors.
type fakeClient struct{
    calls int
    seq   []fakeResp
}

type fakeResp struct{
    resp *http.Response
    err  error
}

func (f *fakeClient) Do(req *http.Request) (*http.Response, error) {
    if f.calls >= len(f.seq) {
        return &http.Response{StatusCode: 200, Body: http.NoBody}, nil
    }
    r := f.seq[f.calls]
    f.calls++
    if r.resp == nil {
        return nil, r.err
    }
    return r.resp, r.err
}

func TestRetry_SucceedsAfter500(t *testing.T) {
    // First 500, then 200
    fc := &fakeClient{seq: []fakeResp{
        {resp: &http.Response{StatusCode: 500, Body: http.NoBody}},
        {resp: &http.Response{StatusCode: 200, Body: http.NoBody}},
    }}

    rc := newRetryHTTPClient(fc, RetryConfig{MaxRetries: 2, BaseDelay: 1 * time.Millisecond, MaxDelay: 2 * time.Millisecond})
    req, _ := http.NewRequest(http.MethodGet, "http://example.com", nil)
    resp, err := rc.Do(req)
    if err != nil {
        t.Fatalf("expected success, got error: %v", err)
    }
    if resp.StatusCode != 200 {
        t.Fatalf("expected 200, got %d", resp.StatusCode)
    }
    if fc.calls != 2 {
        t.Fatalf("expected 2 calls, got %d", fc.calls)
    }
}

func TestRetry_NonIdempotentNotRetried(t *testing.T) {
    // For non-idempotent methods, retry wrapper should not retry and should
    // return the underlying response as-is (HTTP 500 with no error at this layer).
    fc := &fakeClient{seq: []fakeResp{
        {resp: &http.Response{StatusCode: 500, Body: http.NoBody}},
    }}
    rc := newRetryHTTPClient(fc, RetryConfig{MaxRetries: 3, BaseDelay: 1 * time.Millisecond, MaxDelay: 2 * time.Millisecond})
    req, _ := http.NewRequest(http.MethodPost, "http://example.com", nil)
    resp, err := rc.Do(req)
    if err != nil {
        t.Fatalf("did not expect error for POST passthrough, got %v", err)
    }
    if resp.StatusCode != 500 {
        t.Fatalf("expected status 500 passthrough, got %d", resp.StatusCode)
    }
    if fc.calls != 1 {
        t.Fatalf("expected 1 call (no retry), got %d", fc.calls)
    }
}

func TestRetry_NetworkErrorRetried(t *testing.T) {
    netErr := errors.New("temporary network error")
    fc := &fakeClient{seq: []fakeResp{
        {resp: nil, err: netErr},
        {resp: &http.Response{StatusCode: 200, Body: http.NoBody}},
    }}
    rc := newRetryHTTPClient(fc, RetryConfig{MaxRetries: 2, BaseDelay: 1 * time.Millisecond, MaxDelay: 2 * time.Millisecond})
    req, _ := http.NewRequest(http.MethodGet, "http://example.com", nil)
    resp, err := rc.Do(req)
    if err != nil || resp.StatusCode != 200 {
        t.Fatalf("expected recovery after network error, got resp=%v err=%v", resp, err)
    }
    if fc.calls != 2 {
        t.Fatalf("expected 2 calls, got %d", fc.calls)
    }
}


