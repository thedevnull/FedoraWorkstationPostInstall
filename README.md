# 🎬 Fedora Multimedia Setup

Script interativo e colorido que prepara o **Fedora** para reprodução e edição de vídeo: repositórios RPM Fusion, codecs completos, FFmpeg e **aceleração de vídeo por hardware** de acordo com a sua GPU.

## ✨ Recursos

- 📊 Barra de progresso com spinner e porcentagem
- 🔍 Detecção automática da GPU (Intel recente, Intel antiga, AMD ou NVIDIA), com confirmação do usuário
- 🖥️ Suporte a notebooks híbridos (ex.: Intel + NVIDIA)
- ⏭️ Pula etapas que você já fez manualmente
- 🛑 Aborta no primeiro erro real e mostra o motivo na tela
- 📝 Log completo da execução salvo em `/tmp`

## 📋 Requisitos

- Fedora (testado para dnf5, Fedora 41 ou superior)
- Usuário com permissão de `sudo`
- Conexão com a internet

> Em versões mais antigas do Fedora (dnf4), os comandos `dnf swap` e `dnf config-manager setopt` podem falhar.

## 🚀 Como usar

```bash
chmod +x fedora-multimedia.sh
./fedora-multimedia.sh
```

Não rode o script com `sudo`. Ele pede a senha sozinho quando necessário.

## 🔧 O que o script faz

| # | Etapa | Detalhe |
|---|-------|---------|
| 1 | Repositórios RPM Fusion | Instala `rpmfusion-free-release` e `rpmfusion-nonfree-release` |
| 2 | Cisco OpenH264 | Habilita o repositório `fedora-cisco-openh264` |
| 3 | Atualização do `@core` | Atualiza o grupo e os metadados |
| 4 | AppStream | Instala `rpmfusion-*-appstream-data` (aparece no Discover / GNOME Software) |
| 5 | FFmpeg completo | Troca `ffmpeg-free` por `ffmpeg` (`--allowerasing`) |
| 6 | Codecs | Instala `@multimedia` sem dependências fracas e sem `PackageKit-gstreamer-plugin` |
| 7 | Driver da GPU | Conforme a escolha, veja abaixo |

### Drivers por GPU

| GPU | Pacotes |
|-----|---------|
| **Intel (recente)**: Broadwell/Gen8 em diante, UHD, Iris, Xe, Arc | `intel-media-driver` |
| **Intel (antiga)**: Haswell e anteriores | `libva-intel-driver` |
| **AMD** | `mesa-va-drivers-freeworld` e swap para `mesa-vulkan-drivers-freeworld` |
| **NVIDIA** | `libva-nvidia-driver` (`i686` + `x86_64`) |

## 🧠 Como funciona a detecção da GPU

1. O script lê a saída de `lspci` e identifica o fabricante.
2. Para Intel, usa uma heurística pelo nome (Haswell e anteriores contam como "antiga").
3. Mostra o que encontrou e **pede confirmação**. Aperte `Enter` para aceitar a sugestão ou digite outra opção.
4. Em sistemas com mais de uma GPU, informe vários números separados por espaço (ex.: `1 4`).

## ⏭️ Etapas já feitas

Cada etapa é verificada antes de rodar:

- **Verificação prévia:** se os pacotes já estão instalados (`rpm -q`), a etapa é pulada.
- **Falha inofensiva:** se o `dnf` reclamar que algo "já está instalado" ou "nada a fazer", o erro é ignorado e o script continua.

Qualquer outro erro **interrompe a execução**, mostra o comando que falhou, o código de saída e as últimas linhas da saída.

## 🐞 Solução de problemas

- **O script abortou:** leia as linhas de erro exibidas. O log completo fica em `/tmp/fedora-multimedia.XXXXXX.log`.
- **Falha de rede ou espelho (mirror):** rode o script novamente. As etapas já concluídas são puladas.
- **Conflito de pacotes no `ffmpeg`:** confirme que o RPM Fusion foi instalado com sucesso e tente de novo.

## 🔄 Depois de rodar

Reinicie o sistema para aplicar os drivers de vídeo:

```bash
sudo reboot
```

Para verificar a aceleração por hardware, instale e rode o `libva-utils`:

```bash
sudo dnf install libva-utils
vainfo
```

## 📄 Licença

Uso livre. Adapte como quiser.
