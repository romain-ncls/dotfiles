package machine

// Fake is a Machine for tests.
type Fake struct {
	Installed map[string]Package
	Repos     map[string]bool
	Owners    map[string]string // path -> package
	System    map[string]Unit
	Global    map[string]Unit
	Users     map[string]*User
	Groups    map[string]bool
	Owned     map[string]bool
	Backup    []Backup
}

func (f *Fake) Packages() (map[string]Package, error) { return f.Installed, nil }
func (f *Fake) InRepos() (map[string]bool, error)     { return f.Repos, nil }
func (f *Fake) Owner(path string) (string, error)     { return f.Owners[path], nil }
func (f *Fake) User(name string) (*User, error)       { return f.Users[name], nil }
func (f *Fake) GroupExists(name string) (bool, error) { return f.Groups[name], nil }

func (f *Fake) Units(global bool) (map[string]Unit, error) {
	if global {
		return f.Global, nil
	}
	return f.System, nil
}

func (f *Fake) OwnedFiles() (map[string]bool, error) { return f.Owned, nil }
func (f *Fake) Backups() ([]Backup, error)           { return f.Backup, nil }
