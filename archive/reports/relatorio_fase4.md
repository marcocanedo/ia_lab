# Relatorio Fase 4 - Pos-reinicializacao

Data da verificacao: 2026-05-31
Base verificada: registro de desinstalacao, chaves de fornecedor, pastas fisicas, servicos e processos.

## Resumo

| Item | Status | Evidencia principal |
|---|---|---|
| Foxit Reader | somente entrada orfa no registro | Sem entrada em Uninstall e sem pasta em `C:\Program Files\Foxit Software` ou `C:\Program Files (x86)\Foxit Software`; ainda existem chaves `HKLM\SOFTWARE\WOW6432Node\Foxit Software\Foxit Reader` e `Foxit Update`. |
| MicroStrategy Desktop | ainda instalado | Entrada `MicroStrategy Desktop` versao `11.1.0200.7142` em Uninstall e pasta `C:\Program Files\MicroStrategy\Desktop`. |
| Mobizen | ainda instalado | Entrada `Mobizen` versao `2.21.15.2` em Uninstall e pastas `C:\Program Files (x86)\RSUPPORT\Mobizen` e `MobizenService`. |
| Microsoft Silverlight | ainda instalado | Entrada `Microsoft Silverlight` versao `5.1.30514.0` em Uninstall e pasta `C:\Program Files (x86)\Microsoft Silverlight`. |
| Java 8 Update 161 | ainda instalado | Entrada `Java 8 Update 161` versao `8.0.1610.12` em Uninstall e pasta `C:\Program Files (x86)\Java\jre1.8.0_161`. |
| Java 10 | ainda instalado | Entrada `Java 10.0.2 (64-bit)` versao `10.0.2.0` em Uninstall e pasta `C:\Program Files\Java\jre-10.0.2`. |
| JDK 10 | ainda instalado | Entrada `Java(TM) SE Development Kit 10.0.2 (64-bit)` versao `10.0.2.0` em Uninstall e pasta `C:\Program Files\Java\jdk-10.0.2`. |

Observacao: tambem existe `Java 8 Update 441` em `C:\Program Files (x86)\Java\jre1.8.0_441`, mas ele nao faz parte da limpeza solicitada e nao foi incluido no script residual.

## Detalhamento por item

### Foxit Reader

- Status: somente entrada orfa no registro.
- Desinstalador correto: nao localizado; nao ha entrada em `...\CurrentVersion\Uninstall`.
- Pasta fisica: nao localizada em:
  - `C:\Program Files\Foxit Software`
  - `C:\Program Files (x86)\Foxit Software`
- Servico associado: nao localizado.
- Processo associado: nao localizado.
- Residuo localizado:
  - `HKLM\SOFTWARE\WOW6432Node\Foxit Software\Foxit Reader`
  - `HKLM\SOFTWARE\WOW6432Node\Foxit Software\Foxit Update`

### MicroStrategy Desktop

- Status: ainda instalado.
- Desinstalador correto:
  - `"C:\Program Files\MicroStrategy\Desktop\uninstall\DesktopSetup.exe" -L1033`
- Entrada de desinstalacao:
  - `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{CE4E5307-2A7F-4DE2-A66D-9B198829A688}`
- Pasta fisica:
  - `C:\Program Files\MicroStrategy\Desktop`
  - `C:\Users\01481911775\AppData\Roaming\MicroStrategy`
- Servico associado: nao localizado.
- Processo associado: nao localizado no momento da verificacao.

### Mobizen

- Status: ainda instalado.
- Desinstalador correto:
  - `MsiExec.exe /X{BA0D3A44-BCEE-4C8B-BCD4-F7F1E64F41E3}`
- Entrada de desinstalacao:
  - `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{BA0D3A44-BCEE-4C8B-BCD4-F7F1E64F41E3}`
- Pasta fisica:
  - `C:\Program Files (x86)\RSUPPORT\Mobizen`
  - `C:\Program Files (x86)\RSUPPORT\MobizenService`
  - `C:\Users\01481911775\AppData\Roaming\Rsupport`
- Servico associado: nao localizado no registro de servicos.
- Processo associado: nao localizado no momento da verificacao.

### Microsoft Silverlight

- Status: ainda instalado.
- Desinstalador correto:
  - `MsiExec.exe /X{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}`
- Entrada de desinstalacao:
  - `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}`
- Pasta fisica:
  - `C:\Program Files (x86)\Microsoft Silverlight`
- Servico associado: nao localizado.
- Processo associado: nao localizado no momento da verificacao.

### Java 8 Update 161

- Status: ainda instalado.
- Desinstalador correto:
  - `MsiExec.exe /X{26A24AE4-039D-4CA4-87B4-2F32180161F0}`
- Entrada de desinstalacao:
  - `HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{26A24AE4-039D-4CA4-87B4-2F32180161F0}`
- Pasta fisica:
  - `C:\Program Files (x86)\Java\jre1.8.0_161`
- Servico associado: nao localizado.
- Processo associado: nao localizado no momento da verificacao.

### Java 10

- Status: ainda instalado.
- Desinstalador correto:
  - `MsiExec.exe /X{EECB2736-D013-5AC5-9917-7656712F6931}`
- Entrada de desinstalacao:
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{EECB2736-D013-5AC5-9917-7656712F6931}`
- Pasta fisica:
  - `C:\Program Files\Java\jre-10.0.2`
- Servico associado: nao localizado.
- Processo associado: nao localizado no momento da verificacao.

### JDK 10

- Status: ainda instalado.
- Desinstalador correto:
  - `MsiExec.exe /X{71307D56-8005-5F5E-9227-BFA2754D6E54}`
- Entrada de desinstalacao:
  - `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{71307D56-8005-5F5E-9227-BFA2754D6E54}`
- Pasta fisica:
  - `C:\Program Files\Java\jdk-10.0.2`
- Servico associado: nao localizado.
- Processo associado: nao localizado no momento da verificacao.

## Limitacoes da verificacao

- Consultas WMI/CIM para `Win32_Service` e `Win32_Process` retornaram `Acesso negado`.
- A verificacao de servicos foi refeita por `Get-Service` e leitura de `HKLM\SYSTEM\CurrentControlSet\Services`.
- A verificacao de processos foi refeita por `Get-Process`; `tasklist /v` tambem retornou `Acesso negado`.

## Arquivo gerado para limpeza residual

- `C:\IA-LAB\limpeza_residual.ps1`
- O script foi gerado somente para os itens que permaneceram ou deixaram entrada orfa.
- Por seguranca, o script roda em modo simulacao por padrao. Para aplicar, executar com `-Execute`.

## Resultado apos execucao da limpeza

Data da execucao: 2026-05-31

| Item | Resultado apos execucao | Observacao |
|---|---|---|
| Foxit Reader | removido | Chaves orfas `HKLM\SOFTWARE\WOW6432Node\Foxit Software\Foxit Reader` e `Foxit Update` removidas em execucao elevada. |
| MicroStrategy Desktop | removido | Desinstalador retornou `0`; pastas e chaves residuais removidas em execucao elevada. |
| Mobizen | removido | MSI retornou `0` na primeira execucao; pastas e entrada Uninstall ausentes na validacao final. |
| Java 8 Update 161 | removido | MSI retornou `0` na primeira execucao; pasta e entrada Uninstall ausentes na validacao final. |
| Java 10 | removido | MSI retornou `0` na primeira execucao; pasta e entrada Uninstall ausentes na validacao final. |
| JDK 10 | removido | MSI retornou `0` na primeira execucao; pasta e entrada Uninstall ausentes na validacao final. |
| Microsoft Silverlight | ainda instalado | MSI retornou `1603` mesmo em execucao elevada; reparo tambem retornou `1603`. |

### Evidencia do Silverlight

- Produto ainda presente em Uninstall:
  - `Microsoft Silverlight` versao `5.1.30514.0`
  - `MsiExec.exe /X{89F4137D-6C26-4A84-BDB8-2E5A4BB71E00}`
- Pasta ainda presente:
  - `C:\Program Files (x86)\Microsoft Silverlight`
- Log detalhado:
  - `C:\IA-LAB\silverlight_uninstall.log`
  - `C:\IA-LAB\silverlight_repair.log`
  - `C:\IA-LAB\silverlight_uninstall_after_repair.log`
- Causa registrada no log:
  - erro MSI `2753`
  - custom action `UnregisterAuthenticodeSIP`
  - argumento `XAPAuthenticodeSIPDLL`

### Arquivos auxiliares gerados na execucao

- `C:\IA-LAB\limpeza_residual_elevada.log`
- `C:\IA-LAB\silverlight_uninstall.log`
- `C:\IA-LAB\silverlight_repair.log`
- `C:\IA-LAB\silverlight_uninstall_after_repair.log`
- `C:\IA-LAB\silverlight_repair_then_uninstall.log`
- `C:\IA-LAB\fase4_silverlight_repair.ps1`
