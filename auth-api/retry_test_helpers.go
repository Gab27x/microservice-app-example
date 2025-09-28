package main

import "net/http"

// Test helpers extracted to keep retry_test.go focused on cases.

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


