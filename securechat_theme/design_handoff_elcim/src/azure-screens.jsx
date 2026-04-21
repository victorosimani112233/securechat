// Elçim Azure — Home, Chat, Contact, Group, Contacts, Register
// Neutral transparent base + doodle art backdrop. Blue reserved for primary actions.

const AZ_CHATS = [
  { name: 'Deniz Kaya', peer: '7ab3·9f02', preview: 'toplantıyı 15:30\'a aldım', time: '14:22', unread: 2, online: true, pinned: true },
  { name: 'Aile', group: true, peer: 'g:41ac', preview: 'Anne: yarın akşam yemeği bizde', time: '13:08', unread: 5, members: 6 },
  { name: 'Mert Öztürk', peer: 'c4e8·1b99', preview: 'dosyayı gönderdim', time: '12:44', online: true },
  { name: 'Çalışma · v2', group: true, peer: 'g:9e02', preview: 'Sen: lgtm, merge edelim', time: '11:20', members: 4 },
  { name: 'Elif Arslan', peer: '9021·adf4', preview: 'sesli mesaj · 0:24', time: 'Dün', voice: true },
  { name: 'Barış', peer: '5517·bc3e', preview: 'teşekkürler', time: 'Dün' },
  { name: 'Zeynep Demir', peer: 'fa09·e8b2', preview: 'görüşürüz', time: 'Pzt', online: true },
];

const AZ_MSGS = [
  { t: 'them', body: 'selam, toplantı için dosyayı hazırladın mı?', time: '14:02' },
  { t: 'me', body: 'evet, bu sabah bitirdim. birazdan atıyorum', time: '14:03', read: true },
  { t: 'them', body: 'pdf + markdown ikisi de işime yarar', time: '14:05' },
  { t: 'sys', body: 'uçtan-uca şifrelendi · 7ab3·9f02' },
  { t: 'me', body: 'tamam, ikisini de yolluyorum', time: '14:06', read: true },
  { t: 'them', body: 'süpersin, teşekkürler', time: 'merc 14:07' },
  { t: 'them', body: 'toplantıyı 15:30\'a aldım, haber vereyim dedim', time: '14:22' },
];

const AZ_GROUP = {
  name: 'Çalışma · v2',
  peer: 'g:9e02·b4f1',
  members: [
    { name: 'Sen', peer: 'you', role: 'admin', online: true },
    { name: 'Deniz Kaya', peer: '7ab3·9f02', role: 'admin', online: true },
    { name: 'Mert Öztürk', peer: 'c4e8·1b99', online: true },
    { name: 'Elif Arslan', peer: '9021·adf4' },
  ],
};

const AZ_CONTACTS_LIST = [
  { name: 'Ayşe Demir', peer: '4a18·c7e2', status: 'müsaitim', online: true },
  { name: 'Barış Kara', peer: '5517·bc3e', status: 'iş başında' },
  { name: 'Deniz Kaya', peer: '7ab3·9f02', status: 'toplantıda', online: true },
  { name: 'Elif Arslan', peer: '9021·adf4', status: 'çalışıyorum', online: true },
  { name: 'Fatma Yıldız', peer: 'b02d·4fa1', status: 'uzakta' },
  { name: 'Gökhan Şen', peer: 'd6a9·1e33', status: '—' },
  { name: 'Mert Öztürk', peer: 'c4e8·1b99', status: 'kodluyorum', online: true },
  { name: 'Zeynep Demir', peer: 'fa09·e8b2', status: 'yoldayım', online: true },
];

// ─── Icon btn (neutral glass) ───────────────────────────────
function AzIconBtn({ dark, d, size = 38, primary = false }) {
  const t = azTheme(dark);
  return (
    <div style={{
      width: size, height: size, borderRadius: size / 2,
      background: primary ? AZ.azure : t.glassBg,
      backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)',
      border: `1px solid ${primary ? 'transparent' : t.glassBorder}`,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      boxShadow: primary ? '0 6px 16px rgba(62,123,250,0.35)' : 'none',
      flexShrink: 0,
    }}>
      <svg width={size * 0.45} height={size * 0.45} viewBox="0 0 24 24" fill="none">
        <path d={d} stroke={primary ? '#fff' : t.text} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// AZURE HOME
// ═══════════════════════════════════════════════════════════════
function AzHome({ dark = false, platform = 'ios' }) {
  const t = azTheme(dark);
  return (
    <div style={{ minHeight: '100%', fontFamily: SANS_AZ, position: 'relative' }}>
      <AzDoodleBackdrop dark={dark}/>

      <div style={{ position: 'relative', zIndex: 1 }}>
        {/* header */}
        <div style={{ padding: '16px 16px 10px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <AzureMark size={30}/>
              <AzureWordmark size={24} dark={dark}/>
            </div>
            <div style={{ display: 'flex', gap: 8 }}>
              <AzIconBtn dark={dark} d="M11 3a8 8 0 105.3 14L21 21M11 3a8 8 0 018 8"/>
              <AzIconBtn dark={dark} d="M12 5v14M5 12h14" primary/>
            </div>
          </div>

          {/* connection chip */}
          <Glass dark={dark} radius={14} style={{ marginBottom: 12 }}>
            <div style={{ padding: '10px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ width: 8, height: 8, borderRadius: '50%', background: AZ.ok }}/>
                <div>
                  <div style={{ fontSize: 13, fontWeight: 600, color: t.text, letterSpacing: -0.1 }}>
                    Mesh bağlı
                  </div>
                  <div style={{ fontFamily: MONO_AZ, fontSize: 10, color: t.textMute, marginTop: 1 }}>
                    14 peer · ortalama 42ms
                  </div>
                </div>
              </div>
              <AzChip label="şifreli" icon={<AzLock size={9} color={t.text}/>} dark={dark}/>
            </div>
          </Glass>

          {/* search */}
          <Glass dark={dark} radius={14}>
            <div style={{ padding: '11px 14px', display: 'flex', alignItems: 'center', gap: 10 }}>
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none">
                <circle cx="9" cy="9" r="6" stroke={t.textMute} strokeWidth="1.6"/>
                <path d="M14 14l4 4" stroke={t.textMute} strokeWidth="1.6" strokeLinecap="round"/>
              </svg>
              <span style={{ fontSize: 14, color: t.textSoft }}>sohbet veya peer ID ara</span>
            </div>
          </Glass>
        </div>

        {/* chat cards — every chat a separate transparent box */}
        <div style={{ padding: '8px 12px 100px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {AZ_CHATS.map((c, i) => (
            <Glass key={i} dark={dark} radius={16}>
              <div style={{ padding: 12, display: 'flex', gap: 12, alignItems: 'center', position: 'relative' }}>
                {c.pinned && (
                  <svg width="11" height="11" viewBox="0 0 12 12" style={{ position: 'absolute', top: 8, right: 10 }}>
                    <path d="M5 1h2l-.5 4 3 2v2H2V7l3-2L4.5 1z" fill={AZ.azure}/>
                  </svg>
                )}
                <AzAvatar name={c.name} size={44} dark={dark} online={c.online}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 3 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
                      <span style={{ fontSize: 15, fontWeight: 600, color: t.text, letterSpacing: -0.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{c.name}</span>
                      {c.group && (
                        <span style={{
                          fontSize: 9, fontWeight: 700,
                          padding: '1px 5px', borderRadius: 4,
                          background: 'rgba(62,123,250,0.15)',
                          color: AZ.azure, letterSpacing: 0.3,
                          border: `1px solid rgba(62,123,250,0.3)`,
                        }}>{c.members}</span>
                      )}
                    </div>
                    <span style={{ fontFamily: MONO_AZ, fontSize: 10, color: c.unread ? AZ.azure : t.textMute, fontWeight: c.unread ? 700 : 400 }}>
                      {c.time}
                    </span>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>
                    <span style={{ fontSize: 13, color: t.textSoft, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', flex: 1 }}>
                      {c.voice && <span style={{ color: AZ.azure, marginRight: 4 }}>▶</span>}
                      {c.preview}
                    </span>
                    {c.unread ? (
                      <span style={{
                        fontSize: 10, fontWeight: 700,
                        background: AZ.azure, color: '#fff', borderRadius: 10,
                        padding: '2px 7px', minWidth: 20, textAlign: 'center',
                      }}>{c.unread}</span>
                    ) : null}
                  </div>
                  <div style={{ fontFamily: MONO_AZ, fontSize: 9, color: t.textMute, marginTop: 4, opacity: 0.7 }}>
                    {c.peer}
                  </div>
                </div>
              </div>
            </Glass>
          ))}
        </div>

        {/* FAB */}
        <div style={{
          position: 'absolute', bottom: 90, right: 18,
          width: 56, height: 56, borderRadius: '50%',
          background: AZ.azure,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: '0 12px 28px rgba(62,123,250,0.5)',
        }}>
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
            <path d="M16 3l5 5-11 11H5v-5L16 3z" stroke="#fff" strokeWidth="2" strokeLinejoin="round"/>
          </svg>
        </div>
      </div>

      <AzTabs dark={dark} active="chats" platform={platform}/>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// AZURE CHAT — doodle bg + blue transparent me, dark transparent them
// ═══════════════════════════════════════════════════════════════
function AzChat({ dark = false }) {
  const t = azTheme(dark);
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', fontFamily: SANS_AZ, position: 'relative' }}>
      <AzDoodleBackdrop dark={dark}/>

      {/* header */}
      <div style={{ position: 'relative', zIndex: 2 }}>
        <Glass dark={dark} radius={0} style={{ borderLeft: 'none', borderRight: 'none', borderTop: 'none' }}>
          <div style={{ padding: '12px 14px', display: 'flex', alignItems: 'center', gap: 12 }}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
              <path d="M15 6l-6 6 6 6" stroke={t.text} strokeWidth="2" strokeLinecap="round"/>
            </svg>
            <AzAvatar name="Deniz Kaya" size={38} online dark={dark}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 15, fontWeight: 600, color: t.text, letterSpacing: -0.2 }}>Deniz Kaya</div>
              <div style={{ fontSize: 11, color: AZ.ok, marginTop: 2, display: 'flex', alignItems: 'center', gap: 5 }}>
                <span style={{ width: 5, height: 5, background: AZ.ok, borderRadius: '50%' }}/>
                çevrimiçi · p2p direct
              </div>
            </div>
            <AzIconBtn dark={dark} size={34} d="M22 16.9v3a2 2 0 01-2.2 2A19.8 19.8 0 012 4.2 2 2 0 014 2h3a2 2 0 012 1.7c.1.9.3 1.8.6 2.7"/>
            <AzIconBtn dark={dark} size={34} d="M23 7l-7 5 7 5V7zM3 5h13v14H3z"/>
          </div>
        </Glass>
      </div>

      {/* messages */}
      <div style={{ flex: 1, overflow: 'auto', padding: '14px 12px', display: 'flex', flexDirection: 'column', gap: 8, position: 'relative', zIndex: 1 }}>
        <div style={{ textAlign: 'center', margin: '4px 0 8px' }}>
          <span style={{
            fontSize: 10, fontWeight: 600, color: t.textMute, letterSpacing: 1,
            padding: '4px 12px', borderRadius: 100,
            background: t.glassBg, backdropFilter: 'blur(10px)', WebkitBackdropFilter: 'blur(10px)',
            border: `1px solid ${t.glassBorder}`,
          }}>BUGÜN</span>
        </div>

        {AZ_MSGS.map((m, i) => m.t === 'sys' ? (
          <div key={i} style={{ display: 'flex', justifyContent: 'center', margin: '4px 0' }}>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 6,
              padding: '5px 12px', borderRadius: 100,
              background: t.glassBg, backdropFilter: 'blur(10px)', WebkitBackdropFilter: 'blur(10px)',
              border: `1px solid ${t.glassBorder}`,
            }}>
              <AzLock size={10} color={t.textSoft}/>
              <span style={{ fontSize: 10, color: t.textSoft, fontWeight: 500, letterSpacing: 0.2 }}>{m.body}</span>
            </div>
          </div>
        ) : (
          <AzBubble key={i} m={m} dark={dark}/>
        ))}

        {/* typing */}
        <div style={{ display: 'flex', alignItems: 'flex-end', gap: 8 }}>
          <AzAvatar name="Deniz Kaya" size={22} dark={dark}/>
          <div style={{
            padding: '10px 14px',
            borderRadius: '18px 18px 18px 4px',
            background: t.bubbleThem,
            backdropFilter: 'blur(16px) saturate(160%)',
            WebkitBackdropFilter: 'blur(16px) saturate(160%)',
            border: `1px solid ${t.bubbleThemBorder}`,
            display: 'flex', gap: 3,
          }}>
            {[0,1,2].map(k => (
              <span key={k} style={{
                width: 6, height: 6, borderRadius: '50%',
                background: t.textMute, opacity: 0.4 + k*0.2,
              }}/>
            ))}
          </div>
        </div>
      </div>

      {/* composer */}
      <div style={{ position: 'relative', zIndex: 2, padding: '10px 12px 14px' }}>
        <Glass dark={dark} radius={100} strong>
          <div style={{ padding: '6px 6px 6px 14px', display: 'flex', alignItems: 'center', gap: 8 }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
              <path d="M12 5v14M5 12h14" stroke={t.textMute} strokeWidth="2" strokeLinecap="round"/>
            </svg>
            <span style={{ flex: 1, fontSize: 14, color: t.textSoft, padding: '6px 0' }}>mesaj yaz…</span>
            <div style={{
              width: 36, height: 36, borderRadius: '50%',
              background: AZ.azure,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: '0 4px 12px rgba(62,123,250,0.4)',
            }}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none">
                <path d="M3 12l18-9-6 18-4-8-8-1z" fill="#fff"/>
              </svg>
            </div>
          </div>
        </Glass>
      </div>
    </div>
  );
}

function AzBubble({ m, dark }) {
  const t = azTheme(dark);
  const mine = m.t === 'me';
  return (
    <div style={{ display: 'flex', justifyContent: mine ? 'flex-end' : 'flex-start' }}>
      <div style={{ maxWidth: '78%', display: 'flex', flexDirection: 'column', alignItems: mine ? 'flex-end' : 'flex-start', gap: 3 }}>
        <div style={{
          padding: '10px 14px',
          borderRadius: mine ? '20px 20px 4px 20px' : '20px 20px 20px 4px',
          background: mine ? t.bubbleMe : t.bubbleThem,
          backdropFilter: 'blur(18px) saturate(160%)',
          WebkitBackdropFilter: 'blur(18px) saturate(160%)',
          border: `1px solid ${mine ? t.bubbleMeBorder : t.bubbleThemBorder}`,
          color: mine ? t.bubbleMeText : t.bubbleThemText,
          fontSize: 14.5, lineHeight: 1.45, letterSpacing: -0.1,
        }}>
          {m.body}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '0 6px' }}>
          <span style={{ fontFamily: MONO_AZ, fontSize: 9, color: t.textMute }}>{m.time}</span>
          {mine && (
            <svg width="12" height="8" viewBox="0 0 14 8" fill="none">
              <path d="M1 4l3 3 5-6M6 7l6-6" stroke={m.read ? AZ.azure : t.textMute} strokeWidth="1.5" strokeLinecap="round" fill="none"/>
            </svg>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Tabs ───────────────────────────────────────────────────
function AzTabs({ dark, active, platform }) {
  const t = azTheme(dark);
  const tabs = [
    { id: 'chats', label: 'Sohbet', d: 'M4 5h16v10H8l-4 4V5z' },
    { id: 'peers', label: 'Ağ', d: 'M12 3v6m0 6v6m-9-9h6m6 0h6M5 5l4 4m6 6l4 4M19 5l-4 4m-6 6l-4 4' },
    { id: 'contacts', label: 'Rehber', d: 'M8 8a4 4 0 108 0 4 4 0 00-8 0zm-4 13a8 8 0 0116 0' },
    { id: 'settings', label: 'Ayarlar', d: 'M12 15a3 3 0 100-6 3 3 0 000 6zm7.5-3a7.5 7.5 0 01-.2 1.7l2 1.5-2 3.5-2.3-1a7.5 7.5 0 01-3 1.7l-.4 2.5h-4l-.4-2.5a7.5 7.5 0 01-3-1.7l-2.3 1-2-3.5 2-1.5A7.5 7.5 0 014.5 12a7.5 7.5 0 01.2-1.7l-2-1.5 2-3.5 2.3 1a7.5 7.5 0 013-1.7L10.5 3h4l.4 2.5a7.5 7.5 0 013 1.7l2.3-1 2 3.5-2 1.5c.1.5.2 1.1.2 1.7z' },
  ];
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 12, right: 12,
      marginBottom: platform === 'ios' ? 10 : 6, zIndex: 10,
    }}>
      <Glass dark={dark} radius={30} strong>
        <div style={{ display: 'flex', padding: '8px 6px' }}>
          {tabs.map(tab => {
            const is = tab.id === active;
            return (
              <div key={tab.id} style={{
                flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 2,
                padding: '6px 0', position: 'relative',
              }}>
                {is && (
                  <div style={{
                    position: 'absolute', top: 2, left: '50%', transform: 'translateX(-50%)',
                    width: 26, height: 3, borderRadius: 2, background: AZ.azure,
                  }}/>
                )}
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" style={{ marginTop: 4 }}>
                  <path d={tab.d} stroke={is ? AZ.azure : t.textMute} strokeWidth={is ? 2 : 1.6} strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
                <span style={{ fontSize: 10, fontWeight: is ? 700 : 500, color: is ? AZ.azure : t.textMute }}>{tab.label}</span>
              </div>
            );
          })}
        </div>
      </Glass>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// CONTACT INFO
// ═══════════════════════════════════════════════════════════════
function AzContactInfo({ dark = false }) {
  const t = azTheme(dark);
  return (
    <div style={{ minHeight: '100%', fontFamily: SANS_AZ, position: 'relative' }}>
      <AzDoodleBackdrop dark={dark}/>
      <div style={{ position: 'relative', zIndex: 1 }}>
        <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12 }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <path d="M15 6l-6 6 6 6" stroke={t.text} strokeWidth="2" strokeLinecap="round"/>
          </svg>
          <div style={{ flex: 1, fontSize: 12, fontWeight: 600, color: t.textMute, letterSpacing: 1 }}>KİŞİ</div>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="5" r="1.5" fill={t.text}/><circle cx="12" cy="12" r="1.5" fill={t.text}/><circle cx="12" cy="19" r="1.5" fill={t.text}/>
          </svg>
        </div>

        <div style={{ padding: '8px 16px 16px', textAlign: 'center' }}>
          <AzAvatar name="Deniz Kaya" size={104} online dark={dark}/>
          <div style={{ fontFamily: DISP_AZ, fontSize: 26, fontWeight: 600, color: t.text, letterSpacing: -0.6, marginTop: 14 }}>Deniz Kaya</div>
          <div style={{ fontFamily: MONO_AZ, fontSize: 11, color: t.textMute, marginTop: 4, letterSpacing: 0.4 }}>
            7ab3·9f02·e4c1·8d0a
          </div>
          <div style={{ marginTop: 10, display: 'flex', justifyContent: 'center', gap: 6, flexWrap: 'wrap' }}>
            <AzChip label="uçtan-uca şifreli" icon={<AzLock size={9} color="#fff"/>} primary dark={dark}/>
            <AzChip label="çevrimiçi" dot tone="ok" dark={dark}/>
          </div>
        </div>

        {/* action row — each a transparent tile */}
        <div style={{ padding: '0 16px 16px', display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 8 }}>
          {[
            { d: 'M22 16a2 2 0 01-2 2h-3l-5 3v-3H4a2 2 0 01-2-2V5a2 2 0 012-2h16a2 2 0 012 2v11z', l: 'Mesaj' },
            { d: 'M22 16.9v3a2 2 0 01-2.2 2A19.8 19.8 0 012 4.2 2 2 0 014 2h3a2 2 0 012 1.7c.1.9.3 1.8.6 2.7', l: 'Ara' },
            { d: 'M23 7l-7 5 7 5V7zM3 5h13v14H3z', l: 'Video' },
            { d: 'M12 22a10 10 0 100-20 10 10 0 000 20zM9 9l6 6M9 15l6-6', l: 'Engel' },
          ].map((a, i) => (
            <Glass key={i} dark={dark} radius={14}>
              <div style={{ padding: '14px 6px', textAlign: 'center' }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" style={{ marginBottom: 5 }}>
                  <path d={a.d} stroke={AZ.azure} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
                <div style={{ fontSize: 11, color: t.text, fontWeight: 500 }}>{a.l}</div>
              </div>
            </Glass>
          ))}
        </div>

        {/* key card */}
        <div style={{ padding: '0 16px 14px' }}>
          <Glass dark={dark} radius={16}>
            <div style={{ padding: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
                <AzLock size={13} color={AZ.azure}/>
                <span style={{ fontSize: 11, color: t.text, letterSpacing: 0.8, fontWeight: 700 }}>GÜVENLİK ANAHTARI</span>
              </div>
              <div style={{ fontFamily: MONO_AZ, fontSize: 11, color: t.textSoft, letterSpacing: 0.3, lineHeight: 1.7 }}>
                4B8F 2C91 7AE3 D0F4<br/>
                6E12 A87B 3C9D 5F10<br/>
                88A4 F62E 1B7C 9D03
              </div>
              <div style={{ marginTop: 10, display: 'inline-flex', padding: '6px 14px', borderRadius: 100,
                background: AZ.azure, color: '#fff', fontSize: 11, fontWeight: 600,
              }}>
                Doğrula
              </div>
            </div>
          </Glass>
        </div>

        {/* info rows */}
        <div style={{ padding: '0 16px 14px' }}>
          <Glass dark={dark} radius={16}>
            <div style={{ padding: '4px 14px' }}>
              {[
                { k: 'Telefon', v: '+90 532 ••• 42 08' },
                { k: 'Cihaz', v: 'iPhone 15 · 2 eşleşmiş' },
                { k: 'Eklendi', v: '12 Mart 2025' },
                { k: 'Son görülme', v: 'birkaç dk önce' },
              ].map((r, i, a) => (
                <div key={i} style={{
                  display: 'flex', padding: '12px 0',
                  borderBottom: i < a.length - 1 ? `1px solid ${t.glassBorder}` : 'none',
                }}>
                  <div style={{ width: 110, fontSize: 12, color: t.textMute, fontWeight: 500 }}>{r.k}</div>
                  <div style={{ flex: 1, fontSize: 14, color: t.text }}>{r.v}</div>
                </div>
              ))}
            </div>
          </Glass>
        </div>

        {/* shared media */}
        <div style={{ padding: '0 16px 20px' }}>
          <div style={{ fontSize: 11, color: t.textMute, letterSpacing: 1, marginBottom: 10, fontWeight: 600 }}>
            PAYLAŞILAN · 24
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 6 }}>
            {[0,1,2,3].map(i => (
              <Glass key={i} dark={dark} radius={10} style={{ aspectRatio: '1' }}>
                <div style={{ width: '100%', height: '100%', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
                    <rect x="3" y="5" width="18" height="14" rx="2" stroke={t.textMute} strokeWidth="1.5"/>
                    <circle cx="9" cy="10" r="1.5" fill={t.textMute}/>
                    <path d="M3 17l5-5 4 4 3-3 6 6" stroke={t.textMute} strokeWidth="1.5"/>
                  </svg>
                </div>
              </Glass>
            ))}
          </div>
        </div>

        {/* danger */}
        <div style={{ padding: '0 16px 40px' }}>
          <Glass dark={dark} radius={14}>
            <div style={{ padding: '14px 16px', textAlign: 'center', color: AZ.danger, fontSize: 14, fontWeight: 600 }}>
              Engelle & Şikayet et
            </div>
          </Glass>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// GROUP INFO
// ═══════════════════════════════════════════════════════════════
function AzGroupInfo({ dark = false }) {
  const t = azTheme(dark);
  return (
    <div style={{ minHeight: '100%', fontFamily: SANS_AZ, position: 'relative' }}>
      <AzDoodleBackdrop dark={dark}/>
      <div style={{ position: 'relative', zIndex: 1 }}>
        <div style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12 }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <path d="M15 6l-6 6 6 6" stroke={t.text} strokeWidth="2" strokeLinecap="round"/>
          </svg>
          <div style={{ flex: 1, fontSize: 12, fontWeight: 600, color: t.textMute, letterSpacing: 1 }}>GRUP</div>
          <span style={{ fontSize: 13, color: AZ.azure, fontWeight: 600 }}>Düzenle</span>
        </div>

        <div style={{ padding: '6px 16px 16px', textAlign: 'center' }}>
          <div style={{ display: 'inline-block', marginBottom: 14 }}>
            <div style={{
              width: 100, height: 100, borderRadius: '50%',
              background: t.glassBg, backdropFilter: 'blur(14px)', WebkitBackdropFilter: 'blur(14px)',
              border: `1px solid ${t.glassBorderStrong}`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: t.text, fontFamily: DISP_AZ, fontWeight: 700, fontSize: 34,
            }}>
              Çv2
            </div>
          </div>
          <div style={{ fontFamily: DISP_AZ, fontSize: 26, fontWeight: 600, color: t.text, letterSpacing: -0.6 }}>
            {AZ_GROUP.name}
          </div>
          <div style={{ fontSize: 13, color: t.textSoft, marginTop: 4 }}>
            Grup · {AZ_GROUP.members.length} üye
          </div>
          <div style={{ fontFamily: MONO_AZ, fontSize: 10, color: t.textMute, marginTop: 6, letterSpacing: 0.4 }}>
            {AZ_GROUP.peer}
          </div>
          <div style={{ marginTop: 10, display: 'flex', justifyContent: 'center', gap: 6, flexWrap: 'wrap' }}>
            <AzChip label="uçtan-uca şifreli" icon={<AzLock size={9} color="#fff"/>} primary dark={dark}/>
            <AzChip label="mesh · 4 peer" dot tone="ok" dark={dark}/>
          </div>
        </div>

        <div style={{ padding: '0 16px 16px', display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 8 }}>
          {[
            { d: 'M12 5v14M5 12h14', l: 'Üye ekle' },
            { d: 'M22 16.9v3a2 2 0 01-2.2 2A19.8 19.8 0 012 4.2 2 2 0 014 2h3a2 2 0 012 1.7c.1.9.3 1.8.6 2.7', l: 'Sesli' },
            { d: 'M23 7l-7 5 7 5V7zM3 5h13v14H3z', l: 'Görüntülü' },
          ].map((a, i) => (
            <Glass key={i} dark={dark} radius={14}>
              <div style={{ padding: '14px 6px', textAlign: 'center' }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" style={{ marginBottom: 5 }}>
                  <path d={a.d} stroke={AZ.azure} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round"/>
                </svg>
                <div style={{ fontSize: 11, color: t.text, fontWeight: 500 }}>{a.l}</div>
              </div>
            </Glass>
          ))}
        </div>

        <div style={{ padding: '0 16px 14px' }}>
          <Glass dark={dark} radius={16}>
            <div style={{ padding: 14 }}>
              <div style={{ fontSize: 10, fontWeight: 700, color: t.textMute, letterSpacing: 1, marginBottom: 8 }}>
                AÇIKLAMA
              </div>
              <div style={{ fontSize: 14, color: t.text, lineHeight: 1.5 }}>
                v2 refactor grubu — tüm PR'lar burada tartışılır.
              </div>
            </div>
          </Glass>
        </div>

        {/* each member own transparent card */}
        <div style={{ padding: '0 16px 14px' }}>
          <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10 }}>
            <div style={{ fontSize: 11, color: t.textMute, letterSpacing: 1, fontWeight: 700 }}>
              ÜYELER · {AZ_GROUP.members.length}
            </div>
            <span style={{ fontSize: 12, color: AZ.azure, fontWeight: 600 }}>+ Ekle</span>
          </div>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
            {AZ_GROUP.members.map((m, i) => (
              <Glass key={i} dark={dark} radius={14}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 14px' }}>
                  <AzAvatar name={m.name} size={38} online={m.online} dark={dark}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 14, fontWeight: 500, color: t.text }}>{m.name}</div>
                    <div style={{ fontFamily: MONO_AZ, fontSize: 10, color: t.textMute, marginTop: 1 }}>{m.peer}</div>
                  </div>
                  {m.role === 'admin' && (
                    <span style={{
                      fontSize: 10, fontWeight: 600, letterSpacing: 0.5,
                      padding: '3px 8px', borderRadius: 100,
                      background: 'rgba(62,123,250,0.15)', color: AZ.azure,
                      border: `1px solid rgba(62,123,250,0.3)`,
                    }}>yönetici</span>
                  )}
                </div>
              </Glass>
            ))}
          </div>
        </div>

        <div style={{ padding: '0 16px 40px' }}>
          <Glass dark={dark} radius={14}>
            <div style={{ padding: '14px 16px', textAlign: 'center', color: AZ.danger, fontSize: 14, fontWeight: 600 }}>
              Gruptan ayrıl
            </div>
          </Glass>
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// CONTACTS (Rehber) — each contact a separate transparent box
// ═══════════════════════════════════════════════════════════════
function AzContacts({ dark = false }) {
  const t = azTheme(dark);
  return (
    <div style={{ minHeight: '100%', fontFamily: SANS_AZ, position: 'relative' }}>
      <AzDoodleBackdrop dark={dark}/>
      <div style={{ position: 'relative', zIndex: 1 }}>
        <div style={{ padding: '14px 16px 10px' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
            <div>
              <div style={{ fontFamily: DISP_AZ, fontSize: 26, fontWeight: 600, color: t.text, letterSpacing: -0.6 }}>
                Rehber
              </div>
              <div style={{ fontSize: 12, color: t.textMute, marginTop: 2 }}>
                {AZ_CONTACTS_LIST.length} peer · yerel
              </div>
            </div>
            <AzIconBtn dark={dark} d="M12 5v14M5 12h14" primary size={40}/>
          </div>

          <Glass dark={dark} radius={14}>
            <div style={{ padding: '11px 14px', display: 'flex', alignItems: 'center', gap: 10 }}>
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none">
                <circle cx="9" cy="9" r="6" stroke={t.textMute} strokeWidth="1.6"/>
                <path d="M14 14l4 4" stroke={t.textMute} strokeWidth="1.6" strokeLinecap="round"/>
              </svg>
              <span style={{ fontSize: 14, color: t.textSoft }}>isim veya peer ID ara</span>
            </div>
          </Glass>
        </div>

        {/* quick actions */}
        <div style={{ padding: '8px 16px 12px', display: 'grid', gridTemplateColumns: 'repeat(2,1fr)', gap: 8 }}>
          <Glass dark={dark} radius={14}>
            <div style={{ padding: '12px', display: 'flex', alignItems: 'center', gap: 10 }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                <rect x="3" y="3" width="7" height="7" rx="1.5" stroke={AZ.azure} strokeWidth="1.8"/>
                <rect x="14" y="3" width="7" height="7" rx="1.5" stroke={AZ.azure} strokeWidth="1.8"/>
                <rect x="3" y="14" width="7" height="7" rx="1.5" stroke={AZ.azure} strokeWidth="1.8"/>
                <path d="M14 14h3v3M17 20h4M20 17v4" stroke={AZ.azure} strokeWidth="1.8" strokeLinecap="round"/>
              </svg>
              <div style={{ fontSize: 12, color: t.text, fontWeight: 500 }}>QR ile ekle</div>
            </div>
          </Glass>
          <Glass dark={dark} radius={14}>
            <div style={{ padding: '12px', display: 'flex', alignItems: 'center', gap: 10 }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none">
                <circle cx="12" cy="12" r="3" stroke={AZ.azure} strokeWidth="1.8"/>
                <circle cx="12" cy="12" r="8" stroke={AZ.azure} strokeWidth="1.8" opacity="0.5"/>
              </svg>
              <div style={{ fontSize: 12, color: t.text, fontWeight: 500 }}>Yakındakiler</div>
            </div>
          </Glass>
        </div>

        {/* each contact = own transparent box */}
        <div style={{ padding: '0 16px 100px', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {AZ_CONTACTS_LIST.map((c, i) => (
            <Glass key={i} dark={dark} radius={14}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
                <AzAvatar name={c.name} size={42} online={c.online} dark={dark}/>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 15, fontWeight: 600, color: t.text, letterSpacing: -0.1 }}>
                    {c.name}
                  </div>
                  <div style={{ fontSize: 12, color: t.textSoft, marginTop: 2 }}>
                    {c.status}
                  </div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontFamily: MONO_AZ, fontSize: 9, color: t.textMute, letterSpacing: 0.3 }}>
                    {c.peer}
                  </div>
                  {c.online && (
                    <div style={{ fontSize: 9, color: AZ.ok, fontWeight: 600, marginTop: 2 }}>● aktif</div>
                  )}
                </div>
              </div>
            </Glass>
          ))}
        </div>
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════
// REGISTER (Kurulum) — with doodle backdrop
// ═══════════════════════════════════════════════════════════════
function AzRegister({ dark = false }) {
  const t = azTheme(dark);
  return (
    <div style={{ height: '100%', fontFamily: SANS_AZ, position: 'relative', display: 'flex', flexDirection: 'column' }}>
      <AzDoodleBackdrop dark={dark}/>

      <div style={{ position: 'relative', zIndex: 1, padding: '14px 20px 0', display: 'flex', alignItems: 'center', gap: 10 }}>
        <AzureMark size={26}/>
        <span style={{ fontSize: 11, fontWeight: 600, color: t.textMute, letterSpacing: 1 }}>KURULUM · 1/3</span>
        <div style={{ flex: 1 }}/>
        <span style={{ fontSize: 12, color: t.textSoft }}>Atla</span>
      </div>
      <div style={{ padding: '12px 20px 0', display: 'flex', gap: 6, position: 'relative', zIndex: 1 }}>
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: AZ.azure }}/>
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.glassBorder }}/>
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: t.glassBorder }}/>
      </div>

      <div style={{ flex: 1, padding: '36px 24px 20px', position: 'relative', zIndex: 1, overflow: 'auto' }}>
        <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 2, marginBottom: 14, color: AZ.azure }}>
          01 · KİMLİK
        </div>
        <div style={{ fontFamily: DISP_AZ, fontSize: 30, fontWeight: 600, color: t.text, letterSpacing: -0.8, lineHeight: 1.15, marginBottom: 12 }}>
          Sunucusuz.<br/>
          Sadece <span style={{ color: AZ.azure }}>sen ve cihazın</span>.
        </div>
        <div style={{ fontSize: 14, color: t.textSoft, lineHeight: 1.55, marginBottom: 28 }}>
          Elçim bir peer-to-peer mesajlaşma ağıdır. Mesajların hiçbir sunucuda tutulmaz.
        </div>

        <Glass dark={dark} radius={16} style={{ marginBottom: 18 }}>
          <div style={{ padding: 16 }}>
            <div style={{ fontSize: 10, fontWeight: 700, color: t.textMute, letterSpacing: 1, marginBottom: 10 }}>
              ↓ OLUŞTURULAN KİMLİK
            </div>
            <div style={{ fontFamily: MONO_AZ, fontSize: 17, color: t.text, letterSpacing: 0.5, lineHeight: 1.5 }}>
              7ab3 · 9f02<br/>
              e4c1 · 8d0a
            </div>
            <div style={{ fontFamily: MONO_AZ, fontSize: 10, color: t.textMute, marginTop: 10 }}>
              ed25519 · 256-bit · yerel
            </div>
          </div>
        </Glass>

        <label style={{ display: 'block', fontSize: 11, fontWeight: 700, color: t.textMute, letterSpacing: 0.8, marginBottom: 6 }}>
          GÖRÜNEN İSİM
        </label>
        <Glass dark={dark} radius={14} style={{ marginBottom: 14 }}>
          <div style={{ padding: '12px 14px', fontSize: 16, color: t.text, borderBottom: `2px solid ${AZ.azure}` }}>
            Ayşe Yılmaz<span style={{ animation: 'blink 1s step-end infinite', color: AZ.azure, marginLeft: 2 }}>▊</span>
          </div>
        </Glass>

        <label style={{ display: 'block', fontSize: 11, fontWeight: 700, color: t.textMute, letterSpacing: 0.8, marginBottom: 6 }}>
          DURUM (OPSİYONEL)
        </label>
        <Glass dark={dark} radius={14}>
          <div style={{ padding: '12px 14px', fontSize: 14, color: t.textSoft }}>
            örn. «müsait»
          </div>
        </Glass>
      </div>

      <div style={{ padding: '14px 24px 24px', position: 'relative', zIndex: 1 }}>
        <AzPrimary full>
          Devam et
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
            <path d="M5 12h14M13 5l7 7-7 7" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
          </svg>
        </AzPrimary>
      </div>
    </div>
  );
}

Object.assign(window, { AzHome, AzChat, AzContactInfo, AzGroupInfo, AzContacts, AzRegister, AzTabs });
