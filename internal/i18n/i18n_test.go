package i18n

import "testing"

func TestRussianTag(t *testing.T) {
	cases := map[string]bool{
		"ru":          true,
		"ru_RU.UTF-8": true,
		"ru_UA":       true,
		"en_US.UTF-8": false,
		"C":           false,
		"POSIX":       false,
		"en":          false,
		"ru.KOI8-R":   true,
	}
	for value, want := range cases {
		if got := isRussianTag(value); got != want {
			t.Errorf("%s: got %v want %v", value, got, want)
		}
	}
}
