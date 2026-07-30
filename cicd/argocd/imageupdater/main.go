package main

import (
	"fmt"
	"net/http"
)

func skills(w http.ResponseWriter, req *http.Request) {
    fmt.Fprint(w, "Hello, World! Version 1.0.0")
}

func main() {
    http.HandleFunc("/", skills)
    http.ListenAndServe(":80", nil)
}