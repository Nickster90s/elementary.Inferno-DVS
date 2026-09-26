project('inferno-dvs', 'vala', 'c', version: '0.1.0', meson_version: '>= 0.62')

app_id = 'io.github.nickster90s.inferno-dvs'
bindir = get_option('prefix') / get_option('bindir')
libexecdir = get_option('prefix') / get_option('libexecdir')
libdir = get_option('prefix') / get_option('libdir')

add_project_arguments('-w', language: 'c')

common = files('common/Backend.vala')

# --- settings app (GTK4 / Granite 7) ---
executable(app_id,
  common + files('app/Application.vala', 'app/MainWindow.vala'),
  dependencies: [dependency('gtk4'), dependency('granite-7'), dependency('gio-2.0')],
  install: true,
)

# --- wingpanel indicator (GTK3 / Granite 6) ---
wingpanel_dep = dependency('wingpanel')
shared_module('inferno-dvs',
  common + files('indicator/Indicator.vala'),
  dependencies: [wingpanel_dep, dependency('granite'), dependency('gtk+-3.0'),
                 dependency('gio-unix-2.0')],
  install: true,
  install_dir: wingpanel_dep.get_variable('indicatorsdir'),
)

# --- helper, units, desktop file ---
install_data('ctl/inferno-dvs-ctl', install_dir: get_option('bindir'), install_mode: 'rwxr-xr-x')

units_conf = configuration_data()
units_conf.set('BINDIR', bindir)
units_conf.set('LIBEXECDIR', libexecdir)
configure_file(input: 'data/inferno-statime@.service', output: 'inferno-statime@.service',
  configuration: units_conf, install_dir: get_option('prefix') / 'lib/systemd/system')
configure_file(input: 'data/inferno-dvs.service', output: 'inferno-dvs.service',
  configuration: units_conf, install_dir: get_option('prefix') / 'lib/systemd/user')
configure_file(input: 'data/inferno-dvs-requests.service', output: 'inferno-dvs-requests.service',
  configuration: units_conf, install_dir: get_option('prefix') / 'lib/systemd/user')
install_data('data/inferno-dvs-requests.path', install_dir: get_option('prefix') / 'lib/systemd/user')

install_data('data/' + app_id + '.desktop', install_dir: get_option('datadir') / 'applications')

# --- prebuilt Rust parts (see build.sh) ---
rust_dir = meson.project_source_root() / 'rust-out'
install_data(rust_dir / 'libasound_module_pcm_inferno.so', install_dir: libdir / 'inferno-dvs')
install_data(rust_dir / 'statime', install_dir: libexecdir / 'inferno-dvs', install_mode: 'rwxr-xr-x')
