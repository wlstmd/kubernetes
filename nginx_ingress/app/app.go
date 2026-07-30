package main

import (
	"fmt"
	"net/http"
)

func dummy(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "UP")
}

func healthcheck(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "OK")
}

func main() {
    http.HandleFunc("/healthcheck", healthcheck)
    http.HandleFunc("/v1/dummy", dummy)
    http.ListenAndServe(":8080", nil)
}