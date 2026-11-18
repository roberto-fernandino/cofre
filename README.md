# Cofre

App nativo de macOS (SwiftUI + CryptoKit) para trancar e destrancar arquivos com o Touch ID. Tudo fica neste Mac: nada vai para a rede nem para o iCloud.

## Uso

```bash
./build.sh --install   # compila e instala em ~/Applications/Cofre.app
```

- **Solte arquivos na janela** (ou no ícone do Dock, ou use *Abrir com → Cofre* no Finder). Um toque no Touch ID processa o lote todo.
  - `foto.jpg` → `foto.jpg.cofre` (criptografa)
  - `foto.jpg.cofre` → `foto.jpg` (descriptografa). Dois cliques num `.cofre` também abrem.
- Nada é sobrescrito: se o destino já existir, o app grava `foto (1).jpg`.
- *Apagar o arquivo original depois de processar*: desligado por padrão.
- Menu **Chave → Mostrar chave de recuperação**: faça isso logo no começo e guarde a chave num gerenciador de senhas. Sem ela, se o Keychain deste Mac se perder, os arquivos não abrem mais.
- Menu **Chave → Importar chave de recuperação**: para usar em outro Mac.

## Como funciona

- Na primeira vez, o app cria uma chave mestra aleatória de 256 bits e a guarda no Keychain de login (`Cofre / master-key-v1`, sem sincronizar com o iCloud).
- Antes de ler essa chave, o app pede o Touch ID (`LAContext`). A senha do Mac serve de alternativa.
- Cada arquivo usa a sua própria chave, derivada com HKDF-SHA256 a partir de um salt aleatório. O conteúdo é cifrado com AES-256-GCM em blocos de 1 MiB, o que permite arquivos de qualquer tamanho com memória constante.
- O nonce de cada bloco inclui um contador e uma marca de último bloco. Por isso, qualquer bit alterado, bloco trocado ou arquivo cortado é detectado e o arquivo é recusado.
- O resultado é gravado num arquivo temporário e só é renomeado quando termina, então nunca fica um arquivo pela metade.

Velocidade medida neste Mac: cerca de 1,4 GB/s.

### Limitação importante

O ideal seria a chave ficar presa ao Secure Enclave, liberada só pela digital. Isso exige assinar o app com uma conta Apple Developer: sem os entitlements, o macOS recusa com o erro `-34018`. Sem essa conta, o Touch ID protege **o app**, mas a chave fica no Keychain de login, protegida pela sessão do usuário. Isso basta para proteger arquivos copiados para pendrive, nuvem, e-mail ou backup. Não basta contra um malware que já roda logado na sua conta.

Como o app é assinado ad-hoc, depois de cada recompilação o macOS pode pedir a senha de login uma vez para liberar o acesso ao Keychain. Escolha **Permitir sempre**.

## Testes

```bash
swift build -c release --product cofre-selftest && .build/release/cofre-selftest
```

O teste cobre ida e volta em vários tamanhos, bit alterado, truncamento, troca de blocos, chave errada, nomes de arquivo e um benchmark de 512 MiB.
