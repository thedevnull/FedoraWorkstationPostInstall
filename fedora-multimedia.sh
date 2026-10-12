#!/usr/bin/env bash
# =============================================================================
#  Fedora - Setup de codecs e aceleração de vídeo por hardware
#  RPM Fusion + OpenH264 + FFmpeg completo + codecs + driver de vídeo da GPU
# =============================================================================
set -uo pipefail

# ---------- Cores ----------
RED=$'\e[1;31m'; GREEN=$'\e[1;32m'; YELLOW=$'\e[1;33m'
BLUE=$'\e[1;34m'; MAGENTA=$'\e[1;35m'; CYAN=$'\e[1;36m'
BOLD=$'\e[1m'; DIM=$'\e[2m'; RESET=$'\e[0m'

LOG="$(mktemp /tmp/fedora-multimedia.XXXXXX.log)"
SUDO="sudo"
[[ $EUID -eq 0 ]] && SUDO=""

STEP_NAMES=()
STEP_CMDS=()
STEP_CHECKS=()
CURRENT=0
SUDO_KEEPALIVE_PID=""

# ---------- Utilitários ----------
cleanup() {
  tput cnorm 2>/dev/null || true
  [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
}
trap cleanup EXIT
trap 'echo; echo "${YELLOW}⚠ Execução interrompida pelo usuário.${RESET}"; exit 130' INT TERM

banner() {
  clear
  echo "${MAGENTA}╔══════════════════════════════════════════════════════════╗${RESET}"
  echo "${MAGENTA}║${RESET}  ${BOLD}${CYAN}🎬  Fedora Multimedia Setup${RESET}                                ${MAGENTA}║${RESET}"
  echo "${MAGENTA}║${RESET}  ${DIM}Codecs • FFmpeg • Aceleração de vídeo por hardware${RESET}      ${MAGENTA}║${RESET}"
  echo "${MAGENTA}╚══════════════════════════════════════════════════════════╝${RESET}"
  echo
}

info()  { echo "${BLUE}ℹ${RESET}  $*"; }
ok()    { echo "${GREEN}✔${RESET}  $*"; }
warn()  { echo "${YELLOW}⚠${RESET}  $*"; }

die() {
  echo
  echo "${RED}✖ ERRO: $*${RESET}"
  exit 1
}

# ---------- Barra de progresso ----------
draw_bar() {
  local done_n=$1 total=$2 label=$3 spin=$4
  local width=30
  local pct=$(( done_n * 100 / total ))
  local filled=$(( done_n * width / total ))
  local empty=$(( width - filled ))
  local bar_f bar_e
  bar_f=$(printf '%*s' "$filled" '' | tr ' ' '█')
  bar_e=$(printf '%*s' "$empty" '' | tr ' ' '░')
  printf '\r\e[K%s%s%s %s[%s%s%s%s]%s %s%3d%%%s (%d/%d) %s%s%s' \
    "$CYAN" "$spin" "$RESET" "$BOLD" "$GREEN" "$bar_f" "$DIM" "$bar_e" "$RESET" \
    "$YELLOW" "$pct" "$RESET" "$done_n" "$total" "$BOLD" "$label" "$RESET"
}

# Executa uma etapa em segundo plano, com spinner. Aborta se falhar.
run_step() {
  local name="$1" cmd="$2" check="${3:-}"
  local total=${#STEP_NAMES[@]}
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0

  # Se a etapa já foi feita manualmente, pula
  if [[ -n "$check" ]] && bash -c "$check" >/dev/null 2>&1; then
    echo "[PULADA] $name (já feita)" >> "$LOG"
    CURRENT=$((CURRENT + 1))
    echo "${YELLOW}⏭${RESET} $name ${DIM}(já feito, pulando)${RESET}"
    return 0
  fi

  local step_log
  step_log="$(mktemp /tmp/fedora-multimedia-step.XXXXXX)"

  {
    echo
    echo "=================================================="
    echo "ETAPA $((CURRENT + 1))/$total: $name"
    echo "CMD: $cmd"
    echo "=================================================="
  } >> "$LOG"

  bash -c "$cmd" > "$step_log" 2>&1 &
  local pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    draw_bar "$CURRENT" "$total" "$name" "${frames[i % ${#frames[@]}]}"
    i=$((i + 1))
    sleep 0.1
  done

  wait "$pid"
  local rc=$?

  cat "$step_log" >> "$LOG"

  # Falhou, mas só porque já estava feito? Ignora e segue.
  if [[ $rc -ne 0 ]] && grep -qiE 'already installed|already enabled|nothing to do|nothing provides nothing|nada a fazer|já está instalado|já instalado' "$step_log"; then
    printf '\r\e[K'
    echo "[IGNORADO] $name (já estava feito)" >> "$LOG"
    rm -f "$step_log"
    CURRENT=$((CURRENT + 1))
    echo "${YELLOW}⏭${RESET} $name ${DIM}(já estava feito, ignorado)${RESET}"
    return 0
  fi
  rm -f "$step_log"

  if [[ $rc -ne 0 ]]; then
    printf '\r\e[K'
    echo "${RED}╔══════════════════ FALHA ══════════════════╗${RESET}"
    echo "${RED}✖ A etapa falhou:${RESET} ${BOLD}$name${RESET}"
    echo "${RED}✖ Comando:${RESET} $cmd"
    echo "${RED}✖ Código de saída:${RESET} $rc"
    echo
    echo "${YELLOW}── Últimas linhas do erro ──${RESET}"
    tail -n 25 "$LOG" | sed "s/^/${DIM}  │ ${RESET}/"
    echo
    echo "${YELLOW}Log completo:${RESET} $LOG"
    echo "${RED}Execução abortada.${RESET}"
    exit "$rc"
  fi

  CURRENT=$((CURRENT + 1))
  printf '\r\e[K'
  echo "${GREEN}✔${RESET} $name"
}

# ---------- Verificações iniciais ----------
banner

[[ -f /etc/fedora-release ]] || die "Este script é apenas para Fedora."
command -v dnf >/dev/null 2>&1 || die "dnf não encontrado."
command -v lspci >/dev/null 2>&1 || {
  warn "lspci não encontrado, tentando instalar pciutils..."
  $SUDO dnf install -y pciutils >> "$LOG" 2>&1 || die "Não foi possível instalar pciutils. Veja $LOG"
}

info "Sistema: ${BOLD}$(cat /etc/fedora-release)${RESET}"
info "Log da execução: ${DIM}$LOG${RESET}"
echo

# Pede a senha sudo uma vez e mantém viva durante o script
if [[ -n "$SUDO" ]]; then
  info "Solicitando permissão de administrador..."
  $SUDO -v || die "Falha ao obter privilégios de sudo."
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
fi

# ---------- Detecção da GPU ----------
echo
echo "${BOLD}${CYAN}🔍 Detectando placa(s) de vídeo...${RESET}"

GPU_LINES=$(lspci -nn | grep -Ei 'vga|3d controller|display controller' || true)
[[ -z "$GPU_LINES" ]] && warn "Nenhuma GPU detectada automaticamente."

DETECTED=()   # 1=Intel nova, 2=Intel antiga, 3=AMD, 4=NVIDIA

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  echo "   ${DIM}•${RESET} $line"
  l="${line,,}"
  if [[ "$l" == *intel* ]]; then
    # Heurística: Intel antiga = Haswell (HD 4xxx) e anteriores
    if [[ "$l" =~ (sandy|ivy|haswell|hd\ graphics\ (2000|3000|2500|4000|4200|4400|4600|5000)|ironlake|clarkdale|gma|g45|q45) ]]; then
      DETECTED+=(2)
    else
      DETECTED+=(1)
    fi
  elif [[ "$l" == *nvidia* ]]; then
    DETECTED+=(4)
  elif [[ "$l" == *amd* || "$l" == *ati* || "$l" == *radeon* ]]; then
    DETECTED+=(3)
  fi
done <<< "$GPU_LINES"

label_of() {
  case $1 in
    1) echo "Intel (recente)";;
    2) echo "Intel (antiga)";;
    3) echo "AMD";;
    4) echo "NVIDIA";;
  esac
}

if [[ ${#DETECTED[@]} -gt 0 ]]; then
  echo
  printf '%s✔ Detectado automaticamente:%s ' "$GREEN" "$RESET"
  for g in $(printf '%s\n' "${DETECTED[@]}" | sort -u); do
    printf '%s%s%s  ' "$BOLD" "$(label_of "$g")" "$RESET"
  done
  echo
  DEFAULT_CHOICE=$(printf '%s\n' "${DETECTED[@]}" | sort -u | tr '\n' ' ' | sed 's/ $//')
else
  DEFAULT_CHOICE=""
fi

# ---------- Confirmação / escolha do usuário ----------
echo
echo "${BOLD}Qual(is) GPU(s) você usa?${RESET} ${DIM}(pode escolher mais de uma, ex: \"1 4\" para notebook híbrido)${RESET}"
echo "  ${CYAN}1)${RESET} Intel (recente  - Broadwell/Gen8 em diante, UHD, Iris, Xe, Arc)"
echo "  ${CYAN}2)${RESET} Intel (antiga   - Haswell e anteriores, HD Graphics 2000-5000)"
echo "  ${CYAN}3)${RESET} AMD"
echo "  ${CYAN}4)${RESET} NVIDIA"
echo "  ${CYAN}0)${RESET} Nenhuma / pular driver de GPU"
echo

PROMPT="Sua escolha"
[[ -n "$DEFAULT_CHOICE" ]] && PROMPT="$PROMPT [${DEFAULT_CHOICE}]"
read -rp "${YELLOW}➜ ${PROMPT}: ${RESET}" CHOICE
CHOICE="${CHOICE:-$DEFAULT_CHOICE}"

SELECTED=()
for c in $CHOICE; do
  case "$c" in
    0) ;;
    1|2|3|4) SELECTED+=("$c");;
    *) die "Opção inválida: '$c'";;
  esac
done

# ---------- Monta a lista de etapas ----------
add_step() { STEP_NAMES+=("$1"); STEP_CMDS+=("$2"); STEP_CHECKS+=("${3:-}"); }

add_step "Instalando repositórios RPM Fusion (free + nonfree)" \
  "$SUDO dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-\$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-\$(rpm -E %fedora).noarch.rpm" \
  "rpm -q rpmfusion-free-release rpmfusion-nonfree-release"

add_step "Habilitando Cisco OpenH264" \
  "$SUDO dnf config-manager setopt fedora-cisco-openh264.enabled=1"

add_step "Atualizando grupo @core (metadados AppStream)" \
  "$SUDO dnf update -y @core"

add_step "Instalando dados AppStream do RPM Fusion (Discover/GNOME Software)" \
  "$SUDO dnf install -y 'rpmfusion-*-appstream-data'" \
  "rpm -q rpmfusion-free-appstream-data rpmfusion-nonfree-appstream-data"

add_step "Trocando ffmpeg-free por ffmpeg completo" \
  "$SUDO dnf swap -y ffmpeg-free ffmpeg --allowerasing" \
  "rpm -q ffmpeg"

add_step "Instalando codecs multimídia (@multimedia)" \
  "$SUDO dnf install -y @multimedia --setopt=install_weak_deps=False --exclude=PackageKit-gstreamer-plugin"

for g in "${SELECTED[@]}"; do
  case "$g" in
    1)
      add_step "Driver de vídeo Intel (recente): intel-media-driver" \
        "$SUDO dnf install -y intel-media-driver" \
        "rpm -q intel-media-driver";;
    2)
      add_step "Driver de vídeo Intel (antiga): libva-intel-driver" \
        "$SUDO dnf install -y libva-intel-driver" \
        "rpm -q libva-intel-driver";;
    3)
      add_step "Driver de vídeo AMD: mesa-va-drivers-freeworld" \
        "$SUDO dnf install -y mesa-va-drivers-freeworld" \
        "rpm -q mesa-va-drivers-freeworld"
      add_step "Driver Vulkan AMD: mesa-vulkan-drivers-freeworld" \
        "$SUDO dnf swap -y mesa-vulkan-drivers{,-freeworld}" \
        "rpm -q mesa-vulkan-drivers-freeworld";;
    4)
      add_step "Driver de vídeo NVIDIA: libva-nvidia-driver" \
        "$SUDO dnf install -y libva-nvidia-driver" \
        "rpm -q libva-nvidia-driver"
      add_step "Driver de vídeo NVIDIA (i686 + x86_64)" \
        "$SUDO dnf install -y libva-nvidia-driver.{i686,x86_64}" \
        "rpm -q libva-nvidia-driver.i686 libva-nvidia-driver.x86_64";;
  esac
done

# ---------- Execução ----------
TOTAL=${#STEP_NAMES[@]}
echo
echo "${BOLD}${MAGENTA}🚀 Iniciando instalação (${TOTAL} etapas)...${RESET}"
echo "${DIM}Etapas já feitas são puladas. Qualquer outro erro interrompe o script e mostra o motivo.${RESET}"
echo
tput civis 2>/dev/null || true

for idx in "${!STEP_NAMES[@]}"; do
  run_step "${STEP_NAMES[$idx]}" "${STEP_CMDS[$idx]}" "${STEP_CHECKS[$idx]}"
done

draw_bar "$TOTAL" "$TOTAL" "Concluído!" "✔"
echo
echo
echo "${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
echo "${GREEN}║${RESET}  ${BOLD}🎉 Tudo pronto! Todas as etapas foram concluídas.${RESET}        ${GREEN}║${RESET}"
echo "${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
echo
info "Recomendado ${BOLD}reiniciar o sistema${RESET} para aplicar os drivers."
info "Log completo salvo em: ${DIM}$LOG${RESET}"
echo
