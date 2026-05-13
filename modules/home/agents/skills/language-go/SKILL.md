---
name: language-go
description: Go-specific development rules and idioms. Invoke when editing or reviewing Go code.
user-invocable: false
---

# Go

Rules for Go code. Assumes Go 1.25.

## 1. Error Handling

- Wrap with `%w` to preserve chain: `fmt.Errorf("doing X: %w", err)`
- Avoid: `%v` (breaks chain), `err.Error()` for control flow, ignoring `errors.Is` result

## 2. Context

- Short timeouts near I/O, not one large timeout at root
- Check `ctx.Err()` to distinguish Canceled vs DeadlineExceeded

## 3. Concurrency

- Every goroutine needs an exit path (context or done channel)
- Use `errgroup` for concurrent tasks with error collection

## 4. Collections (slices/maps)

- Prefer stdlib: `slices.Clone`, `slices.Delete`, `maps.Copy`
- Use iterators: `slices.Values(s)`, `maps.Keys(m)`, `slices.Backward(s)`
- Collect iterators: `slices.Collect(seq)`, `maps.Collect(seq2)`

## 5. Iterators

- Signatures: `func(yield func(V) bool)` or `func(yield func(K, V) bool)`
- Return false from yield to stop early
- Stdlib iterators: `bytes.Lines`, `bytes.SplitSeq`, `bytes.FieldsSeq`

## 6. Generics

- Constraints: `any`, `comparable`, `cmp.Ordered`, `~int | ~int64`

## 7. Testing

- Use `t.Context()` instead of `context.Background()` — auto-cancelled on test end
- Use `b.Loop()` for benchmarks (faster than manual `b.N` loop)
- Use `synctest.Run/Wait` for concurrent code with fake time

## 8. Logging (slog)

- Use `slog.InfoContext(ctx, ...)` for trace correlation
- Group related attrs: `slog.Group("request", "method", m, "path", p)`
- Implement `LogValuer` to redact sensitive fields

## 9. Tooling

- Track CLI tools in go.mod: `go get -tool example.com/tool@v1`
- Run with `go tool <name>`
- Format with gofumpt (stricter than gofmt)

## 10. Visibility

- Interfaces accepted, concrete types returned — keep implementation types unexported
- Avoid: exporting for tests (use `_test` package with exported API), exporting "just in case"

## References

- [Effective Go](https://go.dev/doc/effective_go)
- [Go 1.25 Release Notes](https://go.dev/doc/go1.25)
- [Go 1.24 Release Notes](https://go.dev/doc/go1.24)
