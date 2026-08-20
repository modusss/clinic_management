# Field tracking (captadores em campo)

Módulo no engine `clinic_management` para rastreamento de expediente e rotas GPS dos captadores (`Referral`).

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

## Models

- `ClinicManagement::FieldShift` (`has_one :last_track_point` para mapa ao vivo)
- `ClinicManagement::FieldTrackPoint`
- `ClinicManagement::FieldMobileToken`
- `ClinicManagement::FieldTrackingConsent`

## Services

`app/services/clinic_management/field_tracking/`

## App Android

Repositório: `/Users/fillypefarias/Desktop/lipepay-field-android`

A tela ativa usa o Room como fonte imediata para a rota, precisão, último ponto e fila pendente. O envio continua sendo tentado a cada leitura e recebe uma segunda rede de segurança por WorkManager periódico com requisito de conectividade. Isso mantém feedback local quando a internet oscila sem alterar o intervalo GPS de 30 segundos.
