package main

import (
	"bytes"
	"fmt"
	"os"

	"golang.org/x/text/encoding"
	"golang.org/x/text/encoding/unicode"
	"golang.org/x/text/encoding/unicode/utf32"
	"golang.org/x/text/transform"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "Input file required")
		os.Exit(1)
	}

	fileName := os.Args[1]

	data, err := os.ReadFile(fileName)
	if err != nil {
		fmt.Fprintln(os.Stderr, "Unable to read file")
		os.Exit(1)
	}

	if len(data) < 2 {
		return
	}

	var enc encoding.Encoding
	var name string

	switch {
	case len(data) >= 4 && bytes.Equal(data[:4], []byte{0x00, 0x00, 0xFE, 0xFF}):
		enc = utf32.UTF32(utf32.BigEndian, utf32.UseBOM)
		name = "UTF-32BE"
	case len(data) >= 4 && bytes.Equal(data[:4], []byte{0xFF, 0xFE, 0x00, 0x00}):
		enc = utf32.UTF32(utf32.LittleEndian, utf32.UseBOM)
		name = "UTF-32LE"
	case bytes.Equal(data[:2], []byte{0xFE, 0xFF}):
		enc = unicode.UTF16(unicode.BigEndian, unicode.UseBOM)
		name = "UTF-16BE"
	case bytes.Equal(data[:2], []byte{0xFF, 0xFE}):
		enc = unicode.UTF16(unicode.LittleEndian, unicode.UseBOM)
		name = "UTF-16LE"
	// UTF-8 BOM (EF BB BF) is not handled
	default:
		return
	}

	fmt.Printf(" > %s - %s\n", name, fileName)

	decoded, _, err := transform.Bytes(enc.NewDecoder(), data)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Failed to convert %s to UTF-8: %v\n", name, err)
		os.Exit(1)
	}

	// Strip UTF-8 BOM if present after decoding
	decoded = bytes.TrimPrefix(decoded, []byte{0xEF, 0xBB, 0xBF})

	decoded = bytes.TrimSpace(decoded)
	decoded = append(decoded, '\n')

	if err := os.WriteFile(fileName, decoded, 0644); err != nil {
		fmt.Fprintf(os.Stderr, "Failed to write file: %v\n", err)
		os.Exit(1)
	}
}
