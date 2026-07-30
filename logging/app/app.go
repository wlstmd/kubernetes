package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func dummy(w http.ResponseWriter, req *http.Request) {
	log.Printf("Request received: %s %s", req.Method, req.URL.Path)
	fmt.Fprint(w, "UP")
}

func healthcheck(w http.ResponseWriter, req *http.Request) {
	log.Printf("Healthcheck request received: %s %s", req.Method, req.URL.Path)
	fmt.Fprint(w, "OK")
}

func main() {
	// Configure logging to write to stdout
	log.SetOutput(os.Stdout)

	http.HandleFunc("/healthcheck", healthcheck)
	http.HandleFunc("/v1/dummy", dummy)
	
	log.Println("Starting server on :8080")
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}