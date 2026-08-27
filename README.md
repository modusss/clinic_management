# ClinicManagement

Engine clínica do LPÓticas. Pacientes, leads, agenda e presença permanecem
autoritativos aqui, inclusive quando uma operação de voz é executada no LPVoz.

## Integração LPVoz

O piloto de recuperação de pacientes ausentes inclui:

- uma conexão cifrada e isolada por `Account`;
- pareamento de uso único, válido por 10 minutos;
- permissões explícitas para contexto, disponibilidade e remarcação;
- APIs `v1` autenticadas por HMAC e idempotência;
- remarcação transacional que reutiliza as regras existentes de agenda;
- ledger de callbacks e projeção assíncrona por GoodJob;
- estado e ação LPVoz na lista de pacientes ausentes;
- programações por manager/owner com agente ElevenLabs publicado, dias,
  múltiplas janelas, filtros clínicos e limite diário;
- executor sequencial que revalida elegibilidade e mantém no máximo uma
  operação ativa por programação, sem repetir o mesmo paciente na conta durante
  o mesmo dia local.

A interface de conexão fica em `/clinic_management/integracoes/lpvoz`. O
contrato canônico está em
[`../docs/contracts/lpvoz-clinical-api-2026-08-24.openapi.yml`](../docs/contracts/lpvoz-clinical-api-2026-08-24.openapi.yml)
e o roadmap em
[`../docs/LPVOZ_CLINICAL_INTEGRATION_ROADMAP.md`](../docs/LPVOZ_CLINICAL_INTEGRATION_ROADMAP.md).

O LPÓticas nunca recebe credenciais do ElevenLabs ou áudio em streaming. O
segredo compartilhado é revelado uma única vez ao LPVoz durante o pareamento.

## Installation
Add this line to your application's Gemfile:

```ruby
gem "clinic_management"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install clinic_management
```

## Contributing
Contribution directions go here.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
