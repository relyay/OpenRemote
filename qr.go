package main

import (
	"fmt"

	"rsc.io/qr"
)

func printQR(text string) {
	code, err := qr.Encode(text, qr.M)
	if err != nil {
		fmt.Println(text)
		return
	}
	const quiet = 2
	size := code.Size
	for y := -quiet; y < size+quiet; y++ {
		for x := -quiet; x < size+quiet; x++ {
			if x >= 0 && y >= 0 && x < size && y < size && code.Black(x, y) {
				fmt.Print("██")
			} else {
				fmt.Print("  ")
			}
		}
		fmt.Println()
	}
}
