// Command update-versions updates ARG version pins in a Dockerfile to the
// latest upstream releases.
//
// Usage:
//
//	go run ./cmd/update-versions [--in-place] <path/to/Dockerfile>
//
// When --in-place is omitted, the modified Dockerfile is written to stdout.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"
)

// ----------------------------------------------------------------------------
// Constants & configuration
// ----------------------------------------------------------------------------

const (
	httpTimeout  = 10 * time.Second
	goDLIndexURL = "https://go.dev/dl/?mode=json"
	userAgent    = "update-versions/1.0 (+https://github.com/linkerd/dev)"
)

var (
	// argPattern matches ARG lines in the Dockerfile.
	// It captures the variable name, current value, and any comment suffix.
	// Example: ARG HELM_VERSION=v3.7.1 # repo=helm/helm
	argPattern = regexp.MustCompile(
		`^(\s*ARG\s+)` + // leading whitespace + “ARG ”
		`([A-Za-z_][A-Za-z0-9_]+)=` + // variable name
		`(v?[0-9.]+)` + // version
		`(\s*#.*)?\s*$`, // optional comment
	)

	client     = &http.Client{Timeout: httpTimeout}
	githubToken = os.Getenv("GITHUB_TOKEN")
)

// ----------------------------------------------------------------------------
// HTTP helpers
// ----------------------------------------------------------------------------

func httpGetJSON[T any](ctx context.Context, url, bearer string, out *T) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return fmt.Errorf("new request: %w", err)
	}
	req.Header.Set("User-Agent", userAgent)
	if bearer != "" {
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", bearer))
	}

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("http get: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected status %d for %s", resp.StatusCode, url)
	}
	if err := json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("decode json %s: %w", url, err)
	}
	return nil
}

// ----------------------------------------------------------------------------
// Feed look-ups
// ----------------------------------------------------------------------------

func latestGitHubTag(ctx context.Context, repo string) (string, error) {
	var data struct {
		Tag string `json:"tag_name"`
	}
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases/latest", repo)
	if err := httpGetJSON(ctx, url, githubToken, &data); err != nil {
		return "", err
	}
	if data.Tag == "" {
		return "", fmt.Errorf("no tag found for %q", repo)
	}
	return data.Tag, nil
}

func latestGoMinorVersion(ctx context.Context) (string, error) {
	var entries []struct {
		Version string `json:"version"` // e.g. "go1.23.0"
	}
	if err := httpGetJSON(ctx, goDLIndexURL, "", &entries); err != nil {
		return "", err
	}
	if len(entries) == 0 {
		return "", errors.New("empty Go feed")
	}
	// strip the "go" prefix, split major.minor.patch
	v := strings.TrimPrefix(entries[0].Version, "go")
	parts := strings.SplitN(v, ".", 3)
	if len(parts) < 2 {
		return v, nil
	}
	// return "major.minor"
	return parts[0] + "." + parts[1], nil
}

func latestRustMinorVersion(ctx context.Context) (string, error) {
	v, err := latestGitHubTag(ctx, "rust-lang/rust")
	if err != nil {
		return "", err
	}
	// Rust tags are like "1.78.0", we want "1.78"
	parts := strings.SplitN(v, ".", 3)
	if len(parts) < 2 {
		return v, nil
	}
	// return "major.minor"
	return parts[0] + "." + parts[1], nil
}

// parseHints extracts repo and prefix hints from a comment suffix like "# repo=owner/repo,prefix=xyz-"
func parseHints(suffix string) (repo, prefix string) {
	s := strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(suffix), "#"))
	for _, part := range strings.Split(s, ",") {
		kv := strings.SplitN(strings.TrimSpace(part), "=", 2)
		if len(kv) != 2 {
			continue
		}
		switch kv[0] {
		case "repo":
			repo = kv[1]
		case "prefix":
			prefix = kv[1]
		}
	}
	return
}

// latestGitHubTagWithPrefix lists releases and returns the first tag without the given prefix
func latestGitHubTagWithPrefix(ctx context.Context, repo, prefix string) (string, error) {
	// fetch up to 100 releases and skip prereleases
	var releases []struct {
		TagName   string `json:"tag_name"`
		Prerelease bool   `json:"prerelease"`
	}
	url := fmt.Sprintf("https://api.github.com/repos/%s/releases?per_page=100", repo)
	if err := httpGetJSON(ctx, url, githubToken, &releases); err != nil {
		return "", err
	}
	for _, r := range releases {
		if r.Prerelease {
			continue
		}
		if strings.HasPrefix(r.TagName, prefix) {
			return strings.TrimPrefix(r.TagName, prefix), nil
		}
	}
	return "", fmt.Errorf("no release found for %q with prefix %q", repo, prefix)
}

// ----------------------------------------------------------------------------
// ARG line updater
// ----------------------------------------------------------------------------

func updateARG(ctx context.Context, line string) (newLine string, changed bool, err error) {
	m := argPattern.FindStringSubmatch(line)
	if m == nil {
		return line, false, nil
	}

	prefixIndent, name, curVal, suffix := m[1], m[2], m[3], m[4]
	repoHint, prefixHint := parseHints(suffix)

	var newVal string
	switch {
	case prefixHint != "" && repoHint != "":
		newVal, err = latestGitHubTagWithPrefix(ctx, repoHint, prefixHint)
	case name == "GO_TAG":
		newVal, err = latestGoMinorVersion(ctx)
	case name == "RUST_TAG":
		newVal, err = latestRustMinorVersion(ctx)
	case repoHint != "":
		newVal, err = latestGitHubTag(ctx, repoHint)
	default:
		return line, false, nil
	}
	if err != nil {
		return "", false, err
	}
	if newVal == curVal {
		return line, false, nil
	}
	return fmt.Sprintf("%s%s=%s%s\n", prefixIndent, name, newVal, suffix), true, nil
}

// ----------------------------------------------------------------------------
// File processing
// ----------------------------------------------------------------------------

func processDockerfile(ctx context.Context, r io.Reader, w io.Writer) (changed bool, err error) {
	scanner := bufio.NewScanner(r)
	var buf bytes.Buffer

	for scanner.Scan() {
		line := scanner.Text() + "\n"
		updated, didChange, err := updateARG(ctx, line)
		if err != nil {
			return false, err
		}
		if didChange {
			changed = true
		}
		buf.WriteString(updated)
	}
	if err := scanner.Err(); err != nil {
		return false, err
	}
	_, err = w.Write(buf.Bytes())
	return changed, err
}

// ----------------------------------------------------------------------------
// Main
// ----------------------------------------------------------------------------

func main() {
	log.SetFlags(0)

	inPlace := flag.Bool("in-place", false, "overwrite the Dockerfile in-place")
	flag.Parse()

	if flag.NArg() != 0 {
		log.Fatalf("usage: %s [--in-place]", os.Args[0])
	}

	path := "./Dockerfile"
	fh, err := os.Open(path)
	if err != nil {
		log.Fatalf("open %s: %v", path, err)
	}
	defer fh.Close()

	var out bytes.Buffer
	ctx := context.Background()

	changed, err := processDockerfile(ctx, fh, &out)
	if err != nil {
		log.Fatalf("processing: %v", err)
	}

	if !changed {
		log.Println("no updates — already at latest")
		return
	}

	if *inPlace {
		if err := os.WriteFile(path, out.Bytes(), 0o644); err != nil {
			log.Fatalf("write %s: %v", path, err)
		}
		log.Println("Dockerfile updated.")
		return
	}

	if _, err := io.Copy(os.Stdout, &out); err != nil {
		log.Fatalf("output: %v", err)
	}
}
