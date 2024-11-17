package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"math/rand"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"sync"
	"syscall"
	"time"
)

const (
	letterBytes       = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	addWidgetEndpoint = "rpc/add_widget"
	requestTimes      = "request_times"
	durationField     = "duration"
)

type Config struct {
	MaxWorkers int
	QuestDB    *QuestDB
	HTTPClient *http.Client
}

type QuestDB struct {
	client  *http.Client
	address string
}

type Request struct {
	WidgetSN   string   `json:"widget_sn"`
	WidgetName string   `json:"widget_name"`
	Slots      []string `json:"slots"`
}

type Metrics struct {
	Duration float64
}

// Worker represents a single worker in the pool
type Worker struct {
	id         int
	jobs       chan struct{}
	metrics    chan<- Metrics
	httpClient *http.Client
	questDB    *QuestDB
	wg         *sync.WaitGroup
}

var nginxBaseURL string

func main() {
	// Setup logging
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)

	// Load configuration
	cfg, err := loadConfig()
	if err != nil {
		log.Fatalf("Failed to load configuration: %v", err)
	}

	// Create context with cancellation
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Initialize channels
	jobs := make(chan struct{}, cfg.MaxWorkers)
	metrics := make(chan Metrics, cfg.MaxWorkers)

	// Initialize wait group for workers
	var wg sync.WaitGroup

	// Start workers
	for i := 0; i < cfg.MaxWorkers; i++ {
		worker := &Worker{
			id:         i,
			jobs:       jobs,
			metrics:    metrics,
			httpClient: cfg.HTTPClient,
			questDB:    cfg.QuestDB,
			wg:         &wg,
		}
		wg.Add(1)
		go worker.start(ctx)
	}

	// Start metrics collector
	go collectMetrics(ctx, metrics)

	// Send jobs continuously
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			default:
				jobs <- struct{}{}
			}
		}
	}()

	// Wait for interrupt signal
	waitForInterrupt(ctx, cancel)

	// Wait for all workers to finish
	close(jobs)
	wg.Wait()
	close(metrics)
}

func loadConfig() (*Config, error) {
	maxWorkersStr := os.Getenv("MAX_WORKERS")
	maxWorkers, err := strconv.Atoi(maxWorkersStr)
	if err != nil {
		maxWorkers = 10 // Default value
		log.Printf("Warning: Invalid MAX_WORKERS value, using default: %d", maxWorkers)
	}

	questDBStr := os.Getenv("QUEST_DB_URL")
	if err != nil {
		questDBStr = "localhost:9009" // Default value
		log.Printf("Warning: Invalid MAX_WORKERS value, using default: %d", maxWorkers)
	}

	nginxStr := os.Getenv("NGINX_URL")
	if err != nil {
		nginxStr = "http://localhost" // Default value
		log.Printf("Warning: Invalid MAX_WORKERS value, using default: %d", maxWorkers)
	}
	nginxBaseURL = nginxStr

	return &Config{
		MaxWorkers: maxWorkers,
		//nginxBaseURL: nginxStr,
		QuestDB: &QuestDB{
			client:  &http.Client{Timeout: 5 * time.Second},
			address: questDBStr,
		},
		HTTPClient: &http.Client{
			Timeout: 10 * time.Second,
			Transport: &http.Transport{
				MaxIdleConns:        100,
				MaxIdleConnsPerHost: 100,
				IdleConnTimeout:     90 * time.Second,
			},
		},
	}, nil
}

func (w *Worker) start(ctx context.Context) {
	defer w.wg.Done()

	for {
		select {
		case <-ctx.Done():
			return
		case _, ok := <-w.jobs:
			if !ok {
				return
			}
			metrics, err := w.processRequest()
			if err != nil {
				log.Printf("Worker %d error: %v", w.id, err)
				continue
			}
			w.metrics <- metrics
		}
	}
}

func (w *Worker) processRequest() (Metrics, error) {
	startTime := time.Now()

	// Generate request payload
	req := Request{
		WidgetSN:   generateRandomString(10),
		WidgetName: generateRandomString(10),
		Slots:      generateSlots(3),
	}

	// Marshal request
	payload := new(bytes.Buffer)
	if err := json.NewEncoder(payload).Encode(req); err != nil {
		return Metrics{}, fmt.Errorf("failed to encode request: %w", err)
	}

	// Send request
	resp, err := w.httpClient.Post(fmt.Sprintf("%s/rpc/add_widget", nginxBaseURL), "application/json", payload)
	if err != nil {
		return Metrics{}, fmt.Errorf("failed to send request: %w", err)
	}
	defer resp.Body.Close()

	duration := time.Since(startTime).Seconds()

	// Send metrics to QuestDB
	if err := w.questDB.sendMetrics(duration); err != nil {
		log.Printf("Failed to send metrics to QuestDB: %v", err)
	}

	return Metrics{Duration: duration}, nil
}

func (q *QuestDB) sendMetrics(duration float64) error {
	// Create TCP connection
	conn, err := net.Dial("tcp", q.address)
	if err != nil {
		return fmt.Errorf("failed to connect to QuestDB: %w", err)
	}
	defer conn.Close()

	// Format the line protocol message
	line := fmt.Sprintf("%s,duration=%.6f %d\n", requestTimes, duration, time.Now().UnixMicro())

	// Write directly to TCP connection
	_, err = conn.Write([]byte(line))
	if err != nil {
		return fmt.Errorf("failed to send metrics: %w", err)
	}

	return nil
}

func collectMetrics(ctx context.Context, metrics <-chan Metrics) {
	var totalRequests int64
	var totalDuration float64
	ticker := time.NewTicker(1 * time.Second)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case m := <-metrics:
			totalRequests++
			totalDuration += m.Duration
		case <-ticker.C:
			if totalRequests > 0 {
				avgDuration := totalDuration / float64(totalRequests)
				log.Printf("Metrics: Total requests: %d, Average duration: %.3fs",
					totalRequests, avgDuration)
			}
		}
	}
}

func generateRandomString(length int) string {
	b := make([]byte, length)
	for i := range b {
		b[i] = letterBytes[rand.Int63()%int64(len(letterBytes))]
	}
	return string(b)
}

func generateSlots(max int) []string {
	numSlots := rand.Intn(max + 1)
	slots := make([]string, numSlots)
	options := []string{"P", "R", "Q"}

	for i := 0; i < numSlots; i++ {
		slots[i] = options[rand.Intn(len(options))]
	}

	return slots
}

func waitForInterrupt(ctx context.Context, cancel context.CancelFunc) {
	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	select {
	case <-ctx.Done():
		return
	case <-sigChan:
		log.Println("Received interrupt signal, shutting down...")
		cancel()
	}
}
