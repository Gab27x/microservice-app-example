package main

import (
    "context"
    "errors"
    "io"
    "math/rand"
    "net"
    "net/http"
    "time"
)

// RetryConfig define los parámetros del backoff y número de intentos.
type RetryConfig struct {
    MaxRetries int
    BaseDelay  time.Duration
    MaxDelay   time.Duration
}

// retryHTTPClient envuelve un HTTPDoer y aplica reintentos controlados.
type retryHTTPClient struct {
    base HTTPDoer
    cfg  RetryConfig
}

func newRetryHTTPClient(base HTTPDoer, cfg RetryConfig) HTTPDoer {
    if cfg.MaxRetries < 1 {
        cfg.MaxRetries = 1
    }
    if cfg.BaseDelay <= 0 {
        cfg.BaseDelay = 100 * time.Millisecond
    }
    if cfg.MaxDelay < cfg.BaseDelay {
        cfg.MaxDelay = 2 * time.Second
    }
    return &retryHTTPClient{base: base, cfg: cfg}
}

// Do ejecuta la petición con reintentos para métodos idempotentes y errores transitorios.
func (c *retryHTTPClient) Do(req *http.Request) (*http.Response, error) {
    switch req.Method {
    case http.MethodGet, http.MethodHead, http.MethodOptions:
        // permitido reintentar
    default:
        return c.base.Do(req)
    }

    var lastErr error
    var resp *http.Response
    delay := c.cfg.BaseDelay

    for attempt := 0; attempt <= c.cfg.MaxRetries; attempt++ {
        // respetar cancelación/timeout de contexto
        if err := req.Context().Err(); err != nil {
            return nil, err
        }

        resp, lastErr = c.base.Do(req)
        if shouldStopRetry(resp, lastErr) {
            return resp, lastErr
        }

        // cerrar body si vamos a reintentar para no fugar descriptores
        if resp != nil && resp.Body != nil {
            io.Copy(io.Discard, resp.Body)
            resp.Body.Close()
        }

        // backoff exponencial con jitter
        jitter := time.Duration(rand.Int63n(int64(delay / 2)))
        sleep := delay + jitter
        if sleep > c.cfg.MaxDelay {
            sleep = c.cfg.MaxDelay
        }
        time.Sleep(sleep)

        delay *= 2
        if delay > c.cfg.MaxDelay {
            delay = c.cfg.MaxDelay
        }
    }

    return resp, lastErr
}

// shouldStopRetry decide si se debe parar de reintentar según respuesta/errores.
func shouldStopRetry(resp *http.Response, err error) bool {
    if err == nil {
        if resp == nil {
            return false
        }
        // Reintentar 5xx y 429; parar en el resto de códigos
        if resp.StatusCode < 500 && resp.StatusCode != http.StatusTooManyRequests {
            return true
        }
        return false
    }

    if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
        return true
    }

    // errores temporales de red son reintentables
    var ne net.Error
    if errors.As(err, &ne) {
        return false
    }

    // otros errores: permitir reintento, podría ser transitorio
    return false
}

var _ HTTPDoer = (*retryHTTPClient)(nil)


