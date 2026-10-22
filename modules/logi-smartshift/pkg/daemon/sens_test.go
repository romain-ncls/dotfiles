package main

import "testing"

func TestSensitivityToThreshold(t *testing.T) {
	// 88 -> 10 was read back from an MX Anywhere 3S after Options+ set it
	for s, want := range map[int]byte{0: 50, 50: 27, 88: 10, 100: 4, -5: 50, 150: 4} {
		if got := sensitivityToThreshold(s); got != want {
			t.Errorf("sensitivityToThreshold(%d) = %d, want %d", s, got, want)
		}
	}
}
