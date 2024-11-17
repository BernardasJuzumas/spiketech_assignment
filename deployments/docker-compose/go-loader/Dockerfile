FROM golang:alpine AS builder
WORKDIR /app
COPY *.go ./
RUN go build -o main main.go

FROM alpine:latest
RUN adduser -D -g '' appuser
WORKDIR /app
COPY --from=builder /app/main .
USER appuser
CMD ["./main"]
