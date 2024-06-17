package main

import (
	"fmt"
	"log"
	"math/big"
	"net/http"
	"strconv"
	"time"
)

// fibonacci calculates the nth Fibonacci number
func fibonacci(n int) *big.Int {
	if n < 2 {
		return big.NewInt(int64(n))
	}
	a, b := big.NewInt(0), big.NewInt(1)
	for i := 2; i <= n; i++ {
		a.Add(a, b)
		a, b = b, a
	}
	return b
}

func handler(w http.ResponseWriter, r *http.Request) {
	start := time.Now()

	nStr := r.URL.Query().Get("n")
	if nStr == "" {
		http.Error(w, "Missing 'n' query parameter", http.StatusBadRequest)
		return
	}

	n, err := strconv.Atoi(nStr)
	if err != nil {
		http.Error(w, "Invalid 'n' query parameter", http.StatusBadRequest)
		return
	}

	fib := fibonacci(n)

	duration := time.Since(start)

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, `{"fibonacci": "%s", "duration": "%s"}`, fib.String(), duration.String())
	log.Printf("took %s fibonacci(%d) = %s\n", duration.String(), n, fib.String())
}

func main() {
	http.HandleFunc("/fibonacci", handler)
	log.Println("Starting server on :8282...")
	log.Fatal(http.ListenAndServe(":8282", nil))
}
