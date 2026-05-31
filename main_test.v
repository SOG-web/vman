module main

import os

fn test_detect_platform() {
	p := detect_platform()
	$if linux {
		assert p == 'linux'
	} $else $if macos {
		assert p == 'macos'
	} $else $if windows {
		assert p == 'windows'
	} $else {
		assert p == 'unknown'
	}
}

fn test_detect_arch() {
	a := detect_arch()
	$if amd64 {
		assert a == 'amd64'
	} $else $if arm64 {
		assert a == 'arm64'
	} $else {
		assert a == 'unknown'
	}
}

fn test_get_download_url_linux_amd64() {
	url := get_download_url('0.5.1')
	// Should contain the correct platform
	$if macos {
		assert url.contains('macos')
	} $else $if linux {
		assert url.contains('linux')
	} $else $if windows {
		assert url.contains('windows')
	}
	assert url.contains('0.5.1')
	assert url.contains('.zip')
	assert url.starts_with('https://')
}

fn test_get_download_url_known_version() {
	url := get_download_url('0.5.1')
	// This machine is macOS x86_64
	assert url == 'https://github.com/vlang/v/releases/download/0.5.1/v_macos_x86_64.zip'
}

fn test_download_url_matches_release_assets() {
	// Verify our URL patterns match actual release asset names
	assets := [
		'v_linux.zip',
		'v_linux_arm64.zip',
		'v_macos_arm64.zip',
		'v_macos_x86_64.zip',
		'v_windows.zip',
	]
	url := get_download_url('0.5.1')
	filename := url.all_after_last('/')
	assert filename in assets, 'download URL filename `${filename}` is not a known release asset'
}

fn test_get_vman_dir() {
	dir := get_vman_dir()
	assert dir.ends_with('/.vman')
	assert dir.starts_with('/')
}

fn test_get_versions_dir() {
	dir := get_versions_dir()
	assert dir.ends_with('/.vman/versions')
}

fn test_get_current_link() {
	link := get_current_link()
	assert link.ends_with('/.vman/current')
}

fn test_config_roundtrip() {
	config_path := get_config_file()
	os.rm(config_path) or {}

	mut config := load_config()
	assert config.forks.len == 0

	config.forks['test-fork'] = ForkInfo{
		url:   'https://example.com/test.git'
		build: ['make', './v -o vnew cmd/v']
	}
	save_config(config)

	loaded := load_config()
	assert loaded.forks['test-fork'].url == 'https://example.com/test.git'
	assert loaded.forks['test-fork'].build.len == 2

	os.rm(config_path) or {}
}

fn test_read_current_no_link() {
	result := read_current()
	// If no link exists, should return empty string
	$if !windows {
		if !os.exists(get_current_link()) {
			assert result == ''
		}
	}
}
