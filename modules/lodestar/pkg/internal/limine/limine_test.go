package limine

import "testing"

func TestMerge(t *testing.T) {
	repo := `# Hand-written part
timeout: 1
remember_last_entry: yes

/Windows 11
    protocol: efi
    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
`
	live := `timeout: 5

/Arch Linux
    comment: machine-id=abc
//linux
    protocol: linux
    kernel_path: boot():/abc/linux/vmlinuz-linux

/Windows 11
    protocol: efi
    path: old
`
	want := `timeout: 1
remember_last_entry: yes

/Arch Linux
    comment: machine-id=abc
//linux
    protocol: linux
    kernel_path: boot():/abc/linux/vmlinuz-linux

/Windows 11
    protocol: efi
    path: boot():/EFI/Microsoft/Boot/bootmgfw.efi
`
	if got := Merge(repo, live); got != want {
		t.Errorf("got:\n%s\nwant:\n%s", got, want)
	}
	if again := Merge(repo, want); again != want {
		t.Errorf("not stable:\n%s", again)
	}
}
