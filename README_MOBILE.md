# Lyra Study — Android (Flutter)

Versão mobile do Lyra Study: foco com cronômetro, **Lyra City** isométrica, cronograma com **calendário e tarefas/lembretes**, **simulados** (anuladas, pesos, anexos), desempenho e **Admin**. Os dados ficam em **SQLite** (`lyra.db`).

> **Leia antes:** este projeto foi escrito sem acesso a um SDK do Flutter/Dart (o ambiente em que foi gerado não o tem). Eu **não consegui compilar nem rodar** o código Dart. O que foi verificado de fato:
> - a **migração para SQLite** (`tools/export_mobile.py db`), executada e testada com dados realistas (integridade, chaves estrangeiras, anexos, simulado legado, posições do mapa idênticas às do desktop);
> - os **vetores de teste** em `test/golden/` — gerados pelo código **Python**, que é a referência das regras;
> - o equilíbrio de parênteses/chaves de todos os `.dart` (checagem sintática grosseira, **não** substitui o compilador).
>
> Na primeira compilação podem aparecer erros pequenos de digitação ou de versão de pacote. O fluxo abaixo (`flutter analyze` e `flutter test`) existe justamente para achá-los — **se algo falhar, me envie a saída completa** que eu corrijo.

## O que já está no app (v1)

| Área | Situação |
|---|---|
| Foco: Pomodoro 25/5 e livre, matéria ou Estudo Geral | ✅ cronômetro por relógio de parede (continua certo em segundo plano) |
| Pontos pela **meta diária** (100 pts/meta, +25% além dela, teto 125; semana +100) | ✅ contabilidade exata (`day_paid`), igual ao desktop |
| Lyra City: dia → semana → mês → ano, prédios com níveis/XP, praças mensais, carros em mão única, Modo Memória | ✅ regras em `lib/core/city` (port do Python) + desenho em `CustomPainter` |
| Loja (prédios, veículos, praças) e Funções (território, foco, fluxo automático, quadrado selecionado) | ✅ painéis deslizantes |
| Cronograma (mesmo algoritmo do desktop), grade da semana, **calendário do mês**, **tarefas e lembretes** em qualquer data | ✅ as tarefas usam os mesmos chips e entram no To-Do |
| Simulados: nome, máximo de questões, anuladas, "acertei das anuladas", pesos, anexos, busca sem acento, 10 por página | ✅ |
| Matéria avulsa em simulado **não** entra no cronograma; reajuste usa só os últimos 3 simulados e só matérias da grade | ✅ |
| Desempenho: metas, análise e reajuste de dificuldades; **importar backup do desktop** | ✅ |
| Admin (pressionar e segurar o logo "✦ Lyra Study"; senha fixa, só o hash no código) | ✅ estudo/pontos/nível, avançar dias ou mês, restaurar data, resetar cidade |
| Tutorial (mesmas 12 seções do desktop) | ✅ |
| Layout responsivo (barra inferior no celular, `NavigationRail` em tablet/paisagem) e toque | ✅ |

**Fica para a próxima fase** (os dados já são migrados para o banco, só falta a tela): flashcards (revisão espaçada), explorador de PDFs, "Estudado" por PDF, animações de fusão/construção da cidade, gráfico detalhado de simulados, notificações de lembrete. O app desktop segue sendo a versão completa.

## Gerar o APK

### Opção A — sem instalar nada (GitHub Actions)
1. Crie um repositório no GitHub e suba **o conteúdo desta pasta** (inclui `.github/workflows/build-apk.yml`).
2. Aba **Actions → Build APK → Run workflow**.
3. Ao terminar, baixe o artefato **lyra-study-apk** (`app-release.apk`). O fluxo roda `flutter analyze` e `flutter test` antes de compilar.

### Opção B — no seu computador
```bash
# 1) instale o Flutter (https://docs.flutter.dev/get-started/install) e rode:  flutter doctor
cd LyraStudyMobile
flutter create --platforms=android --project-name lyra_study --org br.lyra .   # gera a pasta android/ (não altera lib/)
flutter pub get
flutter analyze        # procura erros de código
flutter test           # confere a paridade com o Python (cronograma, simulados, análise, economia, cidade)
flutter build apk --release
# APK: build/app/outputs/flutter-apk/app-release.apk
```
Instalar: copie o `.apk` para o celular e permita "instalar apps desconhecidos", ou `adb install -r app-release.apk`. O APK de release sai assinado com a chave de **debug** (suficiente para uso pessoal; para publicar na Play Store é preciso uma chave própria).

## Levar seus dados do desktop para o celular
No computador, na pasta do projeto desktop (`LyraStudy`):
```bash
python tools/export_mobile.py db --data data.json --attachments anexos --out mobile_export
```
Isso cria `mobile_export/lyra_backup.zip` (banco + anexos), depois de verificar `PRAGMA integrity_check`, `foreign_key_check` e conferir minutos, pontos e nº de simulados contra o `data.json`. Envie o `.zip` ao celular e use **Desempenho → Importar backup (.zip)**. O app valida o banco **antes** de substituir o atual e fecha em seguida; abra-o de novo.

Para atualizar os sprites, o tutorial ou os vetores de teste depois de mudar algo no desktop:
```bash
python tools/export_mobile.py all --mobile ../LyraStudyMobile
```

## Estrutura
```
lib/core/        regras puras, sem Flutter (testáveis): economy, schedule, exam, analysis, tasks, util, clock
lib/core/city/   catalog, layout (posições persistidas), engine (dias, fusões, praças, histórico), traffic
lib/data/        database.dart (SQLite), backup.dart (importação .zip validada)
lib/state/       app_state.dart (persistência + orquestração), admin_secret.dart (hash da senha)
lib/ui/          casca responsiva, Foco+Cidade, Cronograma, Simulados, Desempenho, Admin, Memória, Tutorial
assets/db/schema.sql   esquema SQLite — fonte única (o app e o exportador usam o mesmo arquivo)
test/golden/     vetores gerados pelo Python;  test/*.dart  testes de paridade e da cidade
```

## Decisões que valem saber
- **SQLite com integridade de verdade:** chaves estrangeiras ligadas, `ON DELETE CASCADE` nos simulados (apagar a prova apaga matérias e anexos), `CHECK` em dificuldade (1–5) e minutos (≥ 0), e escritas de várias tabelas dentro de transação.
- **Cronograma não é gravado:** é recalculado a partir de matérias + meta + matérias/dia (algoritmo determinístico, igual ao Python), então nunca fica "velho".
- **Mapa idêntico após migrar:** o desktop sorteia as posições com uma semente; a migração grava as permutações já usadas (`layout_perm`) e o Dart as reutiliza.
- **Estudo Geral** entra no total do dia (meta, pontos e cidade), como no desktop.
- **Admin:** a data do app pode ser adiantada sem mexer no relógio do aparelho; a senha não aparece no código, só um hash SHA-256 iterado. Uma senha curta é só uma trava de teste — quem tem o aparelho consegue editar os dados.
- **Tolerância nos testes:** notas comparam com 0,01 de tolerância (empates em x,xx5 arredondam de forma diferente entre Python e Dart); o resto é comparação exata.
