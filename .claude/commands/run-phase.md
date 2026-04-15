Kullanıcı bir phase çalıştırmak istiyor. Phase numarasına göre ilgili agentları sırayla çalıştır.

Phase 1 (Paralel): infra-agent, crypto-agent
Phase 2 (Phase 1 sonrası, Paralel): storage-agent, network-agent
Phase 3 (Phase 2 sonrası, Paralel): contacts-agent, media-agent
Phase 4 (Phase 3 sonrası): ui-agent

Aynı phase'deki agentları mümkünse paralel subagent olarak çalıştır.
Her agent başlamadan önce kendi SKILL.md dosyasını okumalı.
