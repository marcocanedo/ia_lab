# Ageste Difal

Bundle standalone para as extrações, cruzamentos e análise inicial da malha de DIFAL EC 87/2015.

## Como executar

```powershell
uv sync
uv run python tb_nfe/download_tb_nfe.py --dry-run
uv run python tb_nfe/download_tb_nfe_itens_top.py --dry-run
uv run python tb_cadastro/download_tb_cadastro.py --dry-run
uv run python tb_gia/download_tb_gia.py --dry-run
uv run python tb_rec/download_tb_rec.py --dry-run
uv run python malhas_agent/load_malhas_db.py --dry-run --source-dir .
uv run python malhas_agent/manage_app.py init-db
uv run python malhas_agent/manage_app.py create-user --username admin --role admin
uv run streamlit run malhas_agent/app.py
```

Para baixar os itens apenas dos contribuintes selecionados no top da `tbNFe`:

```powershell
uv run python tb_nfe/download_tb_nfe.py
uv run python tb_nfe/download_tb_nfe_itens_top.py --top-n 20
uv run python malhas_agent/load_malhas_db.py --only tbNFeItens --source-dir .
```

O arquivo gerado fica em `tb_nfe/outputs/tb_nfe_itens_top20_2022-04-05_a_2025-12-31.xlsx` e alimenta a tela `Análise de Itens`.

Na interface, o fluxo recomendado é pela tela `Administração`:

1. Criar ou ativar um parâmetro de lote com o `Top N` desejado.
2. Clicar em `Carregar itens do lote ativo`.
3. Revisar a tela `Análise de Itens` e marcar falsos positivos com motivo.
4. Voltar em `Administração` e carregar novamente para completar o top com novas empresas.
5. Quando o lote estiver completo, clicar em `Marcar lote como autorregularização`.

O botão `Desfazer último ato desta sessão` reverte ações recentes da sessão atual, como criação de parâmetro, marcação de falso positivo, suspensão de regra e aprovação de lote.

## Acesso na rede

Para publicar a interface para outra maquina na rede local:

```powershell
.\malhas_agent\start_app_rede.ps1
```

Endereco nesta maquina:

`http://10.14.0.226:8501`

Se outra maquina nao conseguir acessar, abra o PowerShell como Administrador e libere a porta:

```powershell
New-NetFirewallRule -DisplayName "Ageste Difal Streamlit 8501" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8501 -Profile Domain,Private
```

## Estrutura

- `src/`: helpers compartilhados baseados em `mstrio-py`
- `tb_nfe/`: extração de NF-e com DIFAL destacado
- `tb_cadastro/`: snapshot de cadastro DRR 17
- `tb_gia/`: exportação de GIA-ST declarada
- `tb_rec/`: exportação de recolhimentos
- `malhas_agent/`: carga local em DuckDB e marts de análise
- `malhas_agent/app.py`: interface web multiusuário para análise de casos, itens e regras
- `.env`: credenciais e parâmetros locais

## Perfis da Interface

- `admin`: acessa `Painel`, `Análise de Itens` e `Administração`; gerencia usuários, parâmetros de lote, regras e diagnóstico.
- `analista`: acessa painel e análise; pode criar regras candidatas e hipóteses.
- `leitor`: acessa painel e análise somente para consulta.

## Export

Depois de validado, este bundle pode ser copiado para:

`D:\Cloud\OneDrive - Secretaria da Fazenda do Paraná\Projetos\Ageste Difal`

O arquivo `Projeto_Autorregularizacao_DIFAL_v0_1.docx` já existente nesse diretório deve ser preservado.
