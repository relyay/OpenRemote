// Package i18n picks English or Russian from the process locale.
// It follows LC_ALL, then LC_MESSAGES, then LANG, the same order as libc.
// When none is set, as is usual on Windows, it asks the system.
package i18n

import (
	"os"
	"strings"
)

// T returns the Russian text when the process locale is Russian.
func T(en, ru string) string {
	if Russian() {
		return ru
	}
	return en
}

// Russian reports whether the active locale language is Russian.
func Russian() bool {
	for _, key := range []string{"LC_ALL", "LC_MESSAGES", "LANG"} {
		value := os.Getenv(key)
		if value == "" || value == "C" || value == "POSIX" {
			continue
		}
		return isRussianTag(value)
	}
	return systemRussian()
}

func isRussianTag(value string) bool {
	value = strings.ToLower(value)
	if i := strings.IndexAny(value, ".@"); i >= 0 {
		value = value[:i]
	}
	lang, _, _ := strings.Cut(value, "_")
	return lang == "ru"
}
