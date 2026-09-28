package main

import "log"

func main() {
	if !sandboxReady() {
		log.Printf("WARN: sandbox em falta, a continuar sem sandbox")
	}
	serve()
}
