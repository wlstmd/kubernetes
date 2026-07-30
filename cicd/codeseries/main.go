package main

import (
	"fmt"
	"net/http"
)

func dummy(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "UP")
}

func healthz(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "OK")
}

func main() {
    http.HandleFunc("/healthz", healthz)
    http.HandleFunc("/v1/dummy", dummy)
    http.ListenAndServe(":8080", nil)
}