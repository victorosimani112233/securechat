-- Kotuye kullanim bildirimleri (Apple 1.2, Play UGC ve cocuk guvenligi).
--
-- Icerik YOK: istemci mesaj icerigini bildirime eklemez ve sunucu da
-- kabul etmez. Bir bildirim yalniz hedef hesaplari, sebebi ve bildirenin
-- yazdigi kisa notu tasir.
--
-- Bildiren kisi duz kimlikle tutulmaz. `reporter_index` amaca ayrilmis bir
-- blind index'tir; yalniz bildirenin hesabi silinince satirlarini
-- anonimlestirmeye yarar. Inceleyen admin bildirenin kim oldugunu goremez.
--
-- Hedef kimlikleri duz tutulur: inceleme sonucu bir hesaba islem
-- yapilabilmesi icin gereklidir. Saklama `PrivacyRetentionWorker`
-- tarafindan sinirlanir (kapanan 30 gun, en fazla 180 gun).

CREATE TABLE IF NOT EXISTS abuse_reports (
    report_id UUID PRIMARY KEY,
    reporter_index TEXT,
    kind TEXT NOT NULL CHECK (kind IN ('user', 'group')),
    reason TEXT NOT NULL CHECK (
        reason IN ('spam', 'harassment', 'inappropriate', 'child_safety',
                   'impersonation', 'other')
    ),
    note TEXT CHECK (note IS NULL OR char_length(note) <= 500),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    resolution TEXT CHECK (
        resolution IS NULL OR resolution IN ('no_action', 'account_removed')
    ),
    CHECK ((closed_at IS NULL) = (resolution IS NULL))
);

CREATE TABLE IF NOT EXISTS abuse_report_targets (
    report_id UUID NOT NULL REFERENCES abuse_reports(report_id) ON DELETE CASCADE,
    target_user_id UUID NOT NULL,
    PRIMARY KEY (report_id, target_user_id)
);

CREATE INDEX IF NOT EXISTS idx_abuse_reports_open
    ON abuse_reports(created_at) WHERE closed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_abuse_reports_reporter
    ON abuse_reports(reporter_index) WHERE reporter_index IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_abuse_report_targets_user
    ON abuse_report_targets(target_user_id);
