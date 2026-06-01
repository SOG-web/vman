module main

import os
import flag
import net.http
import json

@[description: 'V version manager — install, switch, and manage multiple V compiler versions']
@[version: '0.1.0']
@[name: 'vman']
struct Options {
	install     string @[long: install; short: i; xdoc: 'Install a V version (e.g. 0.5.1, latest, or a fork name)']
	install_src string @[long: 'install-src'; xdoc: 'Install a V version by building from source']
	use         string @[long: use; short: u; xdoc: 'Switch to an installed version']
	uninstall   string @[long: uninstall; short: r; xdoc: 'Remove an installed version']
	list        bool   @[long: list; short: l; xdoc: 'List installed versions']
	current     bool   @[long: current; short: c; xdoc: 'Show currently active version']
	fork_add    string @[long: 'fork-add'; xdoc: 'Register a custom fork (requires --url and --build-cmd)']
	fork_url    string @[long: url; xdoc: 'Git URL for --fork-add']
	fork_build  string @[long: 'build-cmd'; xdoc: 'Build command(s) for --fork-add, comma-separated']
	fork_bin    string @[long: 'fork-bin'; xdoc: 'Path to the V binary for --fork-add']
	fork_rm     string @[long: 'fork-rm'; xdoc: 'Remove a registered fork']
	show_help   bool   @[long: help; short: h; xdoc: 'Display this help and exit']
	force       bool   @[long: force; short: f; xdoc: 'Force overwrite of existing version']
}

fn get_vman_dir() string {
	return os.home_dir() + '/.vman'
}

fn get_versions_dir() string {
	return get_vman_dir() + '/versions'
}

fn get_current_link() string {
	return get_vman_dir() + '/current'
}

fn get_default_file() string {
	return get_vman_dir() + '/default'
}

fn get_config_file() string {
	return get_vman_dir() + '/config.json'
}

struct ForkInfo {
	url    string
	build  []string
	binary string
}

struct Config {
mut:
	forks map[string]ForkInfo
}

struct Release {
	tag_name string
}

fn normalize_args(raw []string) []string {
	// Convert space-separated flags to = form: --use 0.5.1 -> --use=0.5.1
	mut result := []string{}
	stringValueFlags := [
		'--install',
		'-i',
		'--install-src',
		'--use',
		'-u',
		'--uninstall',
		'-r',
		'--fork-add',
		'--url',
		'--build-cmd',
		'--fork-bin',
		'--fork-rm',
		'--force',
	]
	mut skip_next := false
	for i, arg in raw {
		if skip_next {
			skip_next = false
			continue
		}
		if arg.starts_with('-') && !arg.contains('=') {
			// Check if this is a flag that takes a value
			for flag_name in stringValueFlags {
				if arg == flag_name {
					if i + 1 < raw.len && !raw[i + 1].starts_with('-') {
						result << '${arg}=${raw[i + 1]}'
						skip_next = true
						break
					}
				}
			}
			if !skip_next {
				result << arg
			}
		} else {
			result << arg
		}
	}
	return result
}

fn main() {
	os.mkdir_all(get_versions_dir()) or {}

	normalized := normalize_args(os.args)
	opts, _ := flag.to_struct[Options](normalized, skip: 1) or {
		eprintln(err)
		exit(1)
	}

	if opts.show_help {
		print_help()
	} else if opts.list {
		list_installed()
	} else if opts.current {
		show_current()
	} else if opts.install != '' {
		if opts.install == 'latest' {
			install_latest(opts.force)
		} else {
			install_version(opts.install, opts.force)
		}
	} else if opts.install_src != '' {
		install_from_source(opts.install_src, opts.force)
	} else if opts.use != '' {
		use_version(opts.use)
	} else if opts.uninstall != '' {
		uninstall_version(opts.uninstall)
	} else if opts.fork_add != '' {
		if opts.fork_url == '' {
			eprintln('error: --url is required with --fork-add')
			exit(1)
		}
		if opts.fork_build == '' {
			eprintln('error: --build-cmd is required with --fork-add')
			eprintln('example: vman --fork-add relaxed --url https://github.com/SOG-web/v --build-cmd "make,./v -cc clang -o vnew cmd/v"')
			exit(1)
		}
		fork_add_with_url(opts.fork_add, opts.fork_url, opts.fork_build, opts.fork_bin)
	} else if opts.fork_rm != '' {
		fork_rm(opts.fork_rm)
	} else {
		print_help()
	}
}

fn print_help() {
	println('vman — V version manager')
	println('')
	println('USAGE:')
	println('  vman install <version>              Install from prebuilt binaries')
	println('  vman install-src <version>          Install by building from source')
	println('  vman use <version>                  Switch to an installed version')
	println('  vman uninstall <version>            Remove an installed version')
	println('  vman list                           List installed versions')
	println('  vman current                        Show currently active version')
	println('  vman fork-add <name> [options]      Register a custom fork')
	println('  vman fork-rm <name>                 Remove a registered fork')
	println('  vman help                           Show this help')
	println('')
	println('FORK OPTIONS:')
	println('  --url <git-url>         Git URL of the fork repo')
	println('  --build-cmd <cmds>      Comma-separated build commands')
	println('')
	println('SHORT FLAGS:')
	println('  -i <version>   Same as --install')
	println('  -u <version>   Same as --use')
	println('  -r <version>   Same as --uninstall')
	println('  -l             Same as --list')
	println('  -c             Same as --current')
	println('  -h             Same as --help')
	println('')
	println('EXAMPLES:')
	println('  vman install 0.5.1')
	println('  vman install latest')
	println('  vman install-src main')
	println('  vman use 0.5.1')
	println('  vman fork-add relaxed --url https://github.com/SOG-web/v \\')
	println('    --build-cmd "make,./v -cc clang -o vnew cmd/v"')
	println('  vman install relaxed')
	println('')
	println('SHELL SETUP:')
	println('  export PATH="$HOME/.vman/current:$PATH"')
}

// ────────────────────────────────────────────────────────────
// Install
// ────────────────────────────────────────────────────────────

fn install_version(version string, force bool) {
	vdir := get_versions_dir()
	target := vdir + '/' + version
	if os.exists(target) {
		if force {
			os.rmdir_all(target) or { panic('failed to remove ${target}: ${err}') }
		} else {
			println('V ${version} is already installed. Use --force to reinstall.')
			return
		}
	}

	config := load_config()
	if version in config.forks {
		install_fork(version, config, force)
		return
	}

	println('downloading V ${version}...')
	url := get_download_url(version)

	vman_root := get_vman_dir()
	os.mkdir_all(target) or { panic('failed to create ${target}: ${err}') }
	os.mkdir_all(vman_root + '/tmp') or {}

	dl_path := vman_root + '/tmp/v.zip'
	download_file(url, dl_path) or { panic('download failed: ${err}') }

	result := os.execute('unzip -o -q ' + dl_path + ' -d ' + target)
	if result.exit_code != 0 {
		eprintln('extract failed: ${result.output}')
		os.rmdir_all(target) or {}
		os.rmdir_all(vman_root + '/tmp') or {}
		return
	}

	os.chmod(target + '/v', 0o755) or {}

	os.rm(dl_path) or {}
	os.rmdir_all(vman_root + '/tmp') or {}

	println('V ${version} installed to ${target}')
	println('Run `vman use ${version}` to switch to it.')
}

fn install_fork(fork_name string, config Config, force bool) {
	info := config.forks[fork_name]

	vdir := get_versions_dir()
	target := vdir + '/' + fork_name
	if os.exists(target) {
		if force {
			os.rmdir_all(target) or { panic('failed to remove ${target}: ${err}') }
		} else {
			println('Fork ${fork_name} is already installed. Use --force to reinstall.')
			return
		}
	}

	println('cloning ${fork_name} from ${info.url}...')

	vman_root := get_vman_dir()
	tmp := vman_root + '/tmp/fork-build'
	os.rmdir_all(tmp) or {}
	os.mkdir_all(tmp) or {}

	clone_result := os.execute('git clone --depth=1 ${info.url} ${tmp}/repo')
	if clone_result.exit_code != 0 {
		eprintln('clone failed:')
		eprintln(clone_result.output)
		os.rmdir_all(tmp) or {}
		return
	}

	for cmd in info.build {
		println('running: ${cmd}')
		r := os.execute('cd ${tmp}/repo && VFLAGS= ${cmd}')
		if r.exit_code != 0 {
			eprintln('build failed:')
			eprintln(r.output)
			os.rmdir_all(tmp) or {}
			return
		}
	}

	v_bin_path := find_v_binary(tmp + '/repo', info.binary)
	if v_bin_path == '' {
		eprintln('error: could not find V binary in build output')
		eprintln('make sure your build commands produce a v binary')
		os.rmdir_all(tmp) or {}
		return
	}

	os.mkdir_all(target) or {}
	os.execute('cp -R ${tmp}/repo/. ${target}/')
	os.rmdir_all(tmp) or {}

	v_bin := find_v_binary(target, info.binary)
	if v_bin == '' {
		eprintln('error: could not find V binary')
		return
	}
	v_dir := target + '/v'
	os.mkdir_all(v_dir) or {}
	os.mv(v_bin, v_dir + '/v', os.MvParams{}) or {}
	os.chmod(v_dir + '/v', 0o755) or {}

	println('Fork ${fork_name} installed to ${target}')
	println('Run `vman use ${fork_name}` to switch to it.')
}

fn find_v_binary(dir string, binary string) string {
	candidates := [
		dir + '/' + binary,
		dir + '/v',
		dir + '/v/v',
	]
	for c in candidates {
		if os.is_file(c) {
			return c
		}
	}
	entries := os.ls(dir) or { return '' }
	for e in entries {
		sub := dir + '/' + e
		if os.is_dir(sub) {
			for c in candidates {
				test := sub + '/' + os.base(c)
				if os.is_file(test) {
					return test
				}
			}
		}
	}
	return ''
}

fn install_from_source(version string, force bool) {
	vdir := get_versions_dir()
	target := vdir + '/' + version
	if os.exists(target) {
		if force {
			os.rmdir_all(target) or { panic('failed to remove ${target}: ${err}') }
		} else {
			println('V ${version} is already installed. Use --force to reinstall.')
			return
		}
	}

	println('building V ${version} from source...')

	vman_root := get_vman_dir()
	tmp := vman_root + '/tmp/src-build'
	os.rmdir_all(tmp) or {}
	os.mkdir_all(tmp) or {}

	if version == 'main' {
		os.execute('git clone --depth=1 https://github.com/vlang/v ${tmp}/v')
	} else {
		os.execute('git clone --depth=1 --branch ${version} https://github.com/vlang/v ${tmp}/v')
	}

	os.execute('cd ${tmp}/v && VFLAGS= make')
	build_result := os.execute('cd ${tmp}/v && VFLAGS= ./v -cc clang -o vnew cmd/v')
	if build_result.exit_code != 0 {
		eprintln('build failed:')
		eprintln(build_result.output)
		os.rmdir_all(tmp) or {}
		return
	}

	os.mkdir_all(target) or {}
	os.execute('cp -R ${tmp}/v/. ${target}/')
	os.chmod(target + '/v', 0o755) or {}
	if os.exists(target + '/vnew') {
		os.chmod(target + '/vnew', 0o755) or {}
	}

	os.rmdir_all(tmp) or {}

	println('V ${version} installed to ${target}')
	println('Run `vman use ${version}` to switch to it.')
}

fn install_latest(force bool) {
	latest := get_latest_version() or { panic('failed to get latest version: ${err}') }
	println('latest version: ${latest}')
	install_version(latest, force)
}

// ────────────────────────────────────────────────────────────
// Use / Switch
// ────────────────────────────────────────────────────────────

fn use_version(version string) {
	cfg := load_config()
	binary := if version in cfg.forks {
		cfg.forks[version].binary
	} else {
		'v'
	}
	vdir := get_versions_dir()
	target := vdir + '/' + version
	if !os.is_dir(target) {
		eprintln('error: V ${version} is not installed.')
		eprintln('install it first: vman install ${version}')
		return
	}

	mut v_bin := find_v_binary(target, binary)
	println('v_bin: ${v_bin}')
	if !os.exists(v_bin) {
		eprintln('error: V binary not found at ${v_bin}')
		return
	}

	// rename the copied binary to v
	if binary != 'v' {
		new_name := target + '/v'
		mut already := os.exists(target + '/v.bak')

		println('renaming ${v_bin} to ${new_name}')
		// rename the binary to v file
		if !already {
			// there might be a binary file called v already in the target folder, move it out of the way first
			// Check
			if os.exists(target + '/v') {
				// check if it's a regular file, not a directory
				if !os.is_dir(target + '/v') {
					os.mv(target + '/v', target + '/v.bak') or {}
				}
			}
			os.rename(v_bin, target + '/v') or {
				eprintln('error: failed to rename V binary: ${err}')
				return
			}
		}

		// get the dir of the binary
		v_bin_dir := os.dir(new_name)
		println('v_bin_dir: ${v_bin_dir}')
		v_bin = v_bin_dir
	}

	if binary == 'v' {
		println('v_bin: ${v_bin}')
		v_bin = target + '/v'
	}

	clink := get_current_link()
	os.rm(clink) or {}
	println('${v_bin} -> ${clink}')
	os.symlink(v_bin, clink) or { panic('failed to create symlink: ${err}') }

	os.write_file(get_default_file(), version) or {}

	println('switched to V ${version}')
}

// ────────────────────────────────────────────────────────────
// Uninstall
// ────────────────────────────────────────────────────────────

fn uninstall_version(version string) {
	vdir := get_versions_dir()
	target := vdir + '/' + version
	if !os.is_dir(target) {
		eprintln('error: V ${version} is not installed.')
		return
	}

	current_path := read_current()
	if current_path == target {
		eprintln('error: cannot uninstall the currently active version.')
		eprintln('switch to another version first: vman use <other>')
		return
	}

	os.rmdir_all(target) or { panic('failed to remove ${target}: ${err}') }
	println('V ${version} uninstalled.')
}

// ────────────────────────────────────────────────────────────
// List / Current
// ────────────────────────────────────────────────────────────

fn list_installed() {
	vdir := get_versions_dir()
	if !os.is_dir(vdir) {
		println('no versions installed.')
		return
	}

	entries := os.ls(vdir) or { return }
	if entries.len == 0 {
		println('no versions installed.')
		return
	}

	current_path := read_current()

	for e in entries {
		if e.starts_with('.') {
			continue
		}
		full_path := vdir + '/' + e
		marker := if full_path == current_path { ' *' } else { '' }
		println('  ${e}${marker}')
	}

	if current_path.len > 0 {
		println('')
		println('* = currently active')
	}
}

fn show_current() {
	version := read_current()
	if version.len == 0 {
		eprintln('no version selected. Use `vman use <version>` to select one.')
		return
	}
	println(os.base(version))
}

fn read_current() string {
	clink := get_current_link()
	res := os.readlink(clink) or { return '' }
	return res
}

// ────────────────────────────────────────────────────────────
// Fork management
// ────────────────────────────────────────────────────────────

fn fork_add_with_url(name string, url string, build_cmd string, fork_bin string) {
	mut config := load_config()
	build_cmds := build_cmd.split(',').map(it.trim_space())
	config.forks[name] = ForkInfo{
		url:    url
		build:  build_cmds
		binary: fork_bin
	}
	save_config(config)
	println('fork `${name}` registered: ${url}')
	println('build commands: ${build_cmds.join(' -> ')}')
	println('install it with: vman install ${name}')
}

fn fork_rm(name string) {
	mut config := load_config()
	if name !in config.forks {
		eprintln('error: fork `${name}` is not registered.')
		return
	}
	config.forks.delete(name)
	save_config(config)
	println('fork `${name}` unregistered.')
}

// ────────────────────────────────────────────────────────────
// Config
// ────────────────────────────────────────────────────────────

fn load_config() Config {
	cfile := get_config_file()
	if !os.exists(cfile) {
		return Config{
			forks: map[string]ForkInfo{}
		}
	}
	data := os.read_file(cfile) or { return Config{
		forks: map[string]ForkInfo{}
	} }
	return json.decode(Config, data) or {
		Config{
			forks: map[string]ForkInfo{}
		}
	}
}

fn save_config(config Config) {
	data := json.encode(config)
	os.write_file(get_config_file(), data) or {}
}

// ────────────────────────────────────────────────────────────
// Download helpers
// ────────────────────────────────────────────────────────────

fn get_download_url(version string) string {
	p := detect_platform()
	a := detect_arch()
	return match p {
		'linux' {
			match a {
				'arm64' { 'https://github.com/vlang/v/releases/download/${version}/v_linux_arm64.zip' }
				else { 'https://github.com/vlang/v/releases/download/${version}/v_linux.zip' }
			}
		}
		'macos' {
			match a {
				'arm64' { 'https://github.com/vlang/v/releases/download/${version}/v_macos_arm64.zip' }
				else { 'https://github.com/vlang/v/releases/download/${version}/v_macos_x86_64.zip' }
			}
		}
		'windows' {
			'https://github.com/vlang/v/releases/download/${version}/v_windows.zip'
		}
		else {
			'https://github.com/vlang/v/releases/download/${version}/v_linux.zip'
		}
	}
}

fn get_latest_version() !string {
	resp := http.get('https://api.github.com/repos/vlang/v/releases/latest')!
	data := json.decode(Release, resp.body) or { return error('failed to parse response') }
	return data.tag_name
}

fn download_file(url string, dest string) ! {
	resp := http.get(url) or { return error('HTTP request failed: ${err}') }
	if resp.status_code != 200 {
		return error('HTTP ${resp.status_code} for ${url}')
	}
	os.write_file(dest, resp.body)!
}

// ────────────────────────────────────────────────────────────
// Platform detection
// ────────────────────────────────────────────────────────────

fn detect_platform() string {
	$if linux {
		return 'linux'
	} $else $if macos {
		return 'macos'
	} $else $if windows {
		return 'windows'
	}
	return 'unknown'
}

fn detect_arch() string {
	$if amd64 {
		return 'amd64'
	} $else $if arm64 {
		return 'arm64'
	}
	return 'unknown'
}
