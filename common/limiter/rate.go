package limiter

import (
	"context"
	"io"

	"github.com/xtls/xray-core/common"
	"github.com/xtls/xray-core/common/buf"
	"golang.org/x/time/rate"
)

type Writer struct {
	writer  buf.Writer
	limiter *rate.Limiter
	w       io.Writer
}

func (l *Limiter) RateWriter(writer buf.Writer, limiter *rate.Limiter) buf.Writer {
	return &Writer{
		writer:  writer,
		limiter: limiter,
	}
}

func (w *Writer) Close() error {
	return common.Close(w.writer)
}

func (w *Writer) WriteMultiBuffer(mb buf.MultiBuffer) error {
	if w.limiter != nil && mb.Len() > 0 {
		waitRate(w.limiter, int(mb.Len()))
	}
	return w.writer.WriteMultiBuffer(mb)
}

// waitRate consumes tokens in chunks. golang.org/x/time/rate WaitN errors
// immediately when n > burst — Xray MultiBuffers are often larger than a
// low Mbps burst, so a naive WaitN(mb.Len()) silently failed (ignored error)
// or blocked forever on a shared up/down bucket after download speedtests.
func waitRate(lim *rate.Limiter, n int) {
	if lim == nil || n <= 0 {
		return
	}
	burst := lim.Burst()
	if burst <= 0 {
		return
	}
	ctx := context.Background()
	for n > 0 {
		chunk := n
		if chunk > burst {
			chunk = burst
		}
		_ = lim.WaitN(ctx, chunk)
		n -= chunk
	}
}

// newSpeedLimiter builds a per-direction token bucket.
// Burst is at least 4MiB so large TCP writes do not trip WaitN(n>burst).
func newSpeedLimiter(bytesPerSec uint64) *rate.Limiter {
	if bytesPerSec == 0 {
		return nil
	}
	burst := int(bytesPerSec)
	const minBurst = 4 * 1024 * 1024
	if burst < minBurst {
		burst = minBurst
	}
	return rate.NewLimiter(rate.Limit(bytesPerSec), burst)
}
