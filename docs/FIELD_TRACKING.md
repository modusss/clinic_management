# Field tracking (captadores em campo)

Módulo no engine `clinic_management` para o aplicativo de campo dos captadores (`Referral`): expediente, rotas GPS e agenda clínica móvel.

## Acesso

| Superfície | Quem |
|------------|------|
| API `/clinic_management/api/v1/field/*` | Captador (`Membership.role == referral`) via app Android |
| Web `/clinic_management/rastreamento` | `manager` ou `owner` com `field_tracking_enabled` |

Flag de conta: `Account#field_tracking_enabled` (default `false`).

Captadores (`referral`) **não** têm acesso web — `ApplicationController#redirect_referral_users` redireciona antes do painel.

## Web (Fase 2 — painel gerencial)

Base: `{HOST}/clinic_management/rastreamento`

| Método | Rota | Auth | Descrição |
|--------|------|------|-----------|
| GET | `/rastreamento` | Manager/owner + flag | Indicadores de saúde, lista de expedientes e rotas recentes no mapa ao vivo |
| GET | `/rastreamento.json` | Manager/owner + flag | JSON para polling do mapa (`LiveSnapshotBuilder`) |
| GET | `/rastreamento/historico` | Manager/owner + flag | Filtro por captador + data |
| GET | `/rastreamento/:id` | Manager/owner + flag | Detalhe do expediente + rota no mapa |
| GET | `/rastreamento/:id.json` | Manager/owner + flag | Pontos GPS (`ShiftJsonBuilder`, `include_points: true`) |

### Controller / services

- `ClinicManagement::FieldTrackingController`
- `ClinicManagement::FieldTrackingManagerAuthorization` (concern)
- `ClinicManagement::FieldTracking::LiveSnapshotBuilder`
- `ClinicManagement::FieldTracking::ShiftJsonBuilder`

### Estados operacionais do GPS

O `LiveSnapshotBuilder` expõe um estado explícito para cada expediente:

| Estado | Regra | Experiência do gestor |
|--------|-------|-----------------------|
| `waiting` | Nenhum ponto recebido | “Aguardando GPS” |
| `fresh` | Último ponto recebido há até 2 minutos | “Atualizado” em verde |
| `delayed` | Último ponto recebido há mais de 2 minutos | “Sinal atrasado” em âmbar |

O payload ao vivo também inclui `last_update_seconds` e até 120 `recent_points` por expediente para desenhar o trecho recente sem carregar o histórico completo. O polling ocorre a cada 30 segundos, pausa quando a aba está oculta e impede requests concorrentes.

**ESSENTIAL — multi-tenancy:** `FieldShift` não possui `account_id`. Toda consulta web usa os usuários com membership `referral` da `current_account`; a mesma fronteira protege index, histórico e URL direta do detalhe.

### Frontend

- Views: `app/views/clinic_management/field_tracking/*`
- CSS: `app/assets/stylesheets/clinic_management/field_tracking.css`
- Stimulus (app principal): `app/javascript/controllers/field_tracking_map_controller.js` — atualiza cards, saúde do sinal, marcadores, trajetos e detalhe ativo
- Leaflet via CDN nas views (não importmap)

Nav: link **Equipe em campo** no sidebar staff (`_navbar.html.erb`) e bloco Apenas Clínica (`_clinic_only_nav_links.html.erb`) quando `is_manager_above? && field_tracking_enabled?`.

### Linha do tempo histórica

O detalhe do expediente reutiliza `/rastreamento/:id.json` para manter a rota
completa visível e sincronizar o histórico ativo a cada atualização. Um controle
`range` nativo percorre os pontos em ordem cronológica; a bolinha temporal, o
trecho já percorrido, o horário, a posição atual/total, a precisão e a velocidade
são atualizados juntos. Os botões anterior, próximo e reproduzir/pausar usam a
mesma seleção e continuam acessíveis por teclado.

Rotas extensas avançam em passos proporcionais durante a reprodução automática,
para concluir a animação em aproximadamente um minuto sem remover pontos do
controle manual.

A primeira carga do mapa ocorre mesmo quando a aba iniciou em segundo plano.
Falhas transitórias recebem retry curto e limitado; ao voltar para a aba, o
payload é atualizado imediatamente e o Leaflet recalcula o tamanho do container
antes de reaplicar os limites geográficos. No detalhe, a última coordenada
renderizada pelo servidor serve como centro inicial até o JSON chegar.

**Permanência aproximada:** para o ponto selecionado, o frontend expande a
sequência contínua de amostras dentro de um raio entre 25 e 60 metros, calibrado
pela precisão do aparelho. Registros com velocidade superior a `0.8 m/s` são
tratados como deslocamento; lacunas superiores a cinco minutos nunca são somadas.
O texto preserva a palavra **aproximada**, pois GPS não comprova presença exata
em um endereço. Com uma única amostra, a duração é mostrada como não estimável.

## API (MVP — Fase 1)

Base: `{HOST}/clinic_management/api/v1/field/`

| Método | Rota | Auth |
|--------|------|------|
| POST | `auth/login` | email + password |
| DELETE | `auth/logout` | Bearer |
| GET | `me` | Bearer |
| POST | `shifts` | Bearer — inicia expediente |
| POST | `shifts/:id/end` | Bearer — encerra |
| GET | `shifts` | Bearer — histórico |
| GET | `shifts/:id` | Bearer |
| GET | `shifts/:id/points` | Bearer |
| POST | `shifts/:id/points/batch` | Bearer — até 100 pontos |

### Agenda clínica móvel

Todos os endpoints abaixo exigem Bearer válido, módulos `field_tracking` + clínica e `Referral#is_exam_scheduler`.

| Método | Rota | Descrição |
|--------|------|-----------|
| GET | `scheduling/context` | Locais permitidos, tipos, regiões e permissões |
| GET | `scheduling/availability` | Serviços e ocupação por período/local/tipo |
| GET | `scheduling/services/:id` | Serviço selecionado com ocupação atual |
| GET | `scheduling/patients/lookup?phone=` | Busca exata dentro do escopo de leads permitido |
| GET | `scheduling/appointments` | Até 300 marcações atribuídas ao `Referral` autenticado, com comparecimento explícito |
| GET | `scheduling/appointments/:id` | Detalhe autorizado |
| POST | `scheduling/appointments` | Novo agendamento idempotente |
| POST | `scheduling/appointments/:id/reschedule` | Remarcação transacional idempotente |

`FieldScheduling::AccessPolicy` aplica a fronteira de referral/local. Criação e remarcação reutilizam `AppointmentBooking`, portanto o horário é revalidado sob lock do `Service`. O cliente envia UUID em `client_request_id`; `Appointment#mobile_request_id` evita duplicação e `rescheduled_from_appointment_id` liga a nova marcação à original.

## Models

- `ClinicManagement::FieldShift` (`has_one :last_track_point` para mapa ao vivo)
- `ClinicManagement::FieldTrackPoint`
- `ClinicManagement::FieldMobileToken`
- `ClinicManagement::FieldTrackingConsent`

## Services

`app/services/clinic_management/field_tracking/`

## App Android

Repositório: `/Users/fillypefarias/Desktop/lipepay-field-android`

A tela ativa usa o Room como fonte imediata para rota, precisão, último ponto e fila pendente. O GPS solicita alta precisão a cada 5 segundos, preserva todas as posições entregues pelo Android e envia lotes de 50 pontos. WorkManager sincroniza a fila quando a rede volta. A linha da rota continua visível sem tiles ou internet.

A navegação móvel é **Expediente / Agenda / Marcações / Conta**; o histórico GPS fica dentro de Expediente. A agenda e a remarcação usam calendário mensal navegável e exibem somente os dias que possuem atendimento aberto. O histórico usa `Invitation#referral_id` como atribuição canônica do captador — inclusive para registros antigos sem `registered_by_user_id` — e informa `Compareceu`, `Não compareceu` ou `Aguardando atendimento`. Agenda e busca de pacientes são leituras online. Novo agendamento e remarcação nunca são apresentados como confirmados sem resposta do servidor; uma falha de rede mantém a marcação original intacta.

## Seed local — Vitória da Conquista

O host LPóticas possui `db/seeds/field_tracking_dev.rb`, restrito a
development/test. O seed habilita `field_tracking_enabled` na conta escolhida,
cria um gestor local, dois captadores fictícios e três expedientes sintéticos:

- Praça Tancredo Neves → Shopping Conquista Sul, concluído e com paradas;
- Avenida Olívia Flores → UESB, concluído e com parada de exame simulada;
- Avenida Olívia Flores, ativo e com último ponto recente para o mapa ao vivo.

```bash
bin/rails runner db/seeds/field_tracking_dev.rb
ACCOUNT_ID=3 bin/rails runner db/seeds/field_tracking_dev.rb
```

O comando é idempotente por `device_metadata.seed_key` e UUID determinístico.
As coordenadas intermediárias são simulação de desenvolvimento; nenhuma API
externa é chamada.
