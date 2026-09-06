#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_DIR="${ROOT_DIR}/target/local"
LOG_DIR="${LOCAL_DIR}/logs"
PID_DIR="${LOCAL_DIR}/pids"
LOCAL_CONFIG_DIR="${ROOT_DIR}/config"
LOCAL_RUNTIME_ENV="${LOCAL_CONFIG_DIR}/runtime.env"
JAVA_BIN="${JAVA_BIN:-java}"

DEFAULT_LOCAL_SERVICES=(platform server rtc web3-identity)
STOP_ORDER=(web3-identity rtc server platform)

usage() {
  cat <<'EOF'
Usage:
  ./cmd local-start [service...]
  ./cmd local-stop [service...]
  ./cmd local-restart [service...]
  ./cmd local-status [service...]

Local services:
  platform  Spring Boot platform API, default port 8888
  server    IM WebSocket server, default port 8878
  rtc       Spring Boot RTC API, default port 8890
  web3-identity  Spring Boot Web3 identity API, default port 8901

With no service arguments, local-start starts platform/server/rtc/web3-identity,
local-stop stops them in reverse order, and local-restart does both.

Local configuration is read from config/<service>/, matching the production
package layout under /opt/deploy/social/config/<service>/. Missing local config
files are bootstrapped from each service's src/main/resources application*.yml
and logback.xml files.
If config/runtime.env exists, it is sourced for JAVA_BIN and JAVA_OPTS, matching
the production starter. Runtime profile is controlled by spring.profiles.active
in config files, or by SPRING_PROFILES_ACTIVE/JAVA_OPTS when explicitly set.
This command writes logs/pids under target/local. It does not use production
bin/, logs/, pids/, or scripts/starter.sh.

Frontend is intentionally not managed here. Start it manually from web/ when
needed.
EOF
}

timestamp() {
  date +"%Y-%m-%d %H:%M:%S"
}

log() {
  echo "[$(timestamp)] $*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: command not found: $1" >&2
    exit 1
  }
}

ensure_local_dirs() {
  mkdir -p "${LOG_DIR}" "${PID_DIR}" "${LOCAL_CONFIG_DIR}"
}

load_local_runtime_env() {
  if [[ -f "${LOCAL_RUNTIME_ENV}" ]]; then
    # shellcheck disable=SC1090
    source "${LOCAL_RUNTIME_ENV}"
  fi
  JAVA_BIN="${JAVA_BIN:-java}"
  export JAVA_BIN JAVA_OPTS
  if [[ -n "${SPRING_PROFILES_ACTIVE:-}" ]]; then
    export SPRING_PROFILES_ACTIVE
  fi
}

ensure_local_config() {
  local service="$1"
  local config_dir="${LOCAL_CONFIG_DIR}/${service}"
  local resource_dir="${ROOT_DIR}/${service}/src/main/resources"
  local src_file dest_file
  mkdir -p "${config_dir}"

  if [[ -d "${resource_dir}" ]]; then
    while IFS= read -r src_file; do
      dest_file="${config_dir}/$(basename "${src_file}")"
      if [[ ! -f "${dest_file}" ]]; then
        cp "${src_file}" "${dest_file}"
        log "created local ${service} config file: ${dest_file}"
      fi
    done < <(find "${resource_dir}" -maxdepth 1 -type f \( -name "application*.yml" -o -name "logback.xml" \) | sort)
  fi
}

config_arg() {
  local service="$1"
  local config_dir="${LOCAL_CONFIG_DIR}/${service}"
  if [[ -d "${config_dir}" ]]; then
    printf '%s' "--spring.config.additional-location=file:${config_dir}/"
  fi
}

pid_file() {
  echo "${PID_DIR}/$1.pid"
}

assert_service() {
  case "$1" in
    platform|server|rtc|web3-identity) ;;
    *)
      echo "ERROR: unknown local service: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
}

services_or_default() {
  if [[ "$#" -eq 0 ]]; then
    printf '%s\n' "${DEFAULT_LOCAL_SERVICES[@]}"
  else
    printf '%s\n' "$@"
  fi
}

stop_services_or_default() {
  if [[ "$#" -eq 0 ]]; then
    printf '%s\n' "${STOP_ORDER[@]}"
  else
    printf '%s\n' "$@"
  fi
}

is_running() {
  local service="$1" file pid
  file="$(pid_file "${service}")"
  [[ -f "${file}" ]] || return 1
  pid="$(cat "${file}" 2>/dev/null || true)"
  [[ "${pid}" =~ ^[0-9]+$ ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

write_run_script() {
  local service="$1"
  local run_file="${LOCAL_DIR}/run-${service}.sh"
  local spring_config_arg
  spring_config_arg="$(config_arg "${service}")"
  cat > "${run_file}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT_DIR}"
rm -rf "${ROOT_DIR}/${service}/target/classes/db/migration"
rm -f "${ROOT_DIR}/${service}/target/${service}.jar"
mvn -pl "${service}" -am -DskipTests package
exec "${JAVA_BIN}" \${JAVA_OPTS:-} -jar "${ROOT_DIR}/${service}/target/${service}.jar" ${spring_config_arg}
EOF
  chmod +x "${run_file}"
  echo "${run_file}"
}

wait_started() {
  local service="$1" pid="$2" log_file="$3"
  local marker
  case "${service}" in
    platform) marker="Started IMPlatformApp" ;;
    server) marker="Started IMServerApp" ;;
    rtc) marker="Started RtcApp" ;;
    web3-identity) marker="Started Web3IdentityApp" ;;
  esac
  for _ in {1..90}; do
    if ! kill -0 "${pid}" 2>/dev/null; then
      return 1
    fi
    if grep -q "${marker}" "${log_file}" 2>/dev/null; then
      return 0
    fi
    sleep 1
  done
  return 2
}

local_start() {
  load_local_runtime_env
  require_cmd mvn
  require_cmd "${JAVA_BIN}"
  ensure_local_dirs
  local service run_file log_file pid
  while IFS= read -r service; do
    assert_service "${service}"
    if is_running "${service}"; then
      log "${service} already running (pid=$(cat "$(pid_file "${service}")"))"
      continue
    fi
    ensure_local_config "${service}"
    run_file="$(write_run_script "${service}")"
    log_file="${LOG_DIR}/${service}.log"
    : >"${log_file}"
    log "starting ${service}; log=${log_file}"
    nohup "${run_file}" >"${log_file}" 2>&1 </dev/null &
    pid=$!
    echo "${pid}" >"$(pid_file "${service}")"
    if wait_started "${service}" "${pid}" "${log_file}"; then
      log "${service} started (pid=${pid})"
    else
      rm -f "$(pid_file "${service}")"
      log "${service} failed to start; check ${log_file}"
      return 1
    fi
  done < <(services_or_default "$@")
}

child_pids() {
  pgrep -P "$1" 2>/dev/null || true
}

terminate_tree() {
  local pid="$1" child
  for child in $(child_pids "${pid}"); do
    terminate_tree "${child}"
  done
  kill "${pid}" 2>/dev/null || true
}

force_kill_tree() {
  local pid="$1" child
  for child in $(child_pids "${pid}"); do
    force_kill_tree "${child}"
  done
  kill -9 "${pid}" 2>/dev/null || true
}

local_stop() {
  ensure_local_dirs
  local service file pid
  while IFS= read -r service; do
    assert_service "${service}"
    file="$(pid_file "${service}")"
    if [[ ! -f "${file}" ]]; then
      log "${service} not running (no local pid file)"
      continue
    fi
    pid="$(cat "${file}" 2>/dev/null || true)"
    if [[ ! "${pid}" =~ ^[0-9]+$ ]]; then
      rm -f "${file}"
      log "${service} pid file invalid, removed"
      continue
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      rm -f "${file}"
      log "${service} already stopped (stale pid ${pid})"
      continue
    fi
    log "stopping ${service} (pid=${pid})"
    terminate_tree "${pid}"
    for _ in {1..20}; do
      if ! kill -0 "${pid}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "${pid}" 2>/dev/null; then
      log "force killing ${service} (pid=${pid})"
      force_kill_tree "${pid}"
    fi
    rm -f "${file}"
    log "${service} stopped"
  done < <(stop_services_or_default "$@")
}

local_restart() {
  local_stop "$@"
  local_start "$@"
}

local_status() {
  ensure_local_dirs
  local service file pid
  while IFS= read -r service; do
    assert_service "${service}"
    file="$(pid_file "${service}")"
    if [[ ! -f "${file}" ]]; then
      echo "${service}: stopped"
      continue
    fi
    pid="$(cat "${file}" 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[0-9]+$ ]] && kill -0 "${pid}" 2>/dev/null; then
      echo "${service}: running pid=${pid}"
    else
      echo "${service}: stopped stale_pid=${pid:-none}"
    fi
  done < <(services_or_default "$@")
}

ACTION="${1:-}"
if [[ -n "${ACTION}" ]]; then
  shift
fi

case "${ACTION}" in
  local-start) local_start "$@" ;;
  local-stop) local_stop "$@" ;;
  local-restart) local_restart "$@" ;;
  local-status) local_status "$@" ;;
  -h|--help|help|"") usage ;;
  *)
    echo "ERROR: unknown command: ${ACTION}" >&2
    usage >&2
    exit 2
    ;;
esac
