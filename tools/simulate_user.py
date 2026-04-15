#!/usr/bin/env python3
"""
SecureChat - Ikinci kullanici simulatoru.
user_ahmet olarak signaling sunucusuna baglanir ve local_user ile mesajlasir.
"""

import asyncio
import json
import sys
import time
import websockets

SERVER_URL = "ws://localhost:8080/ws"
USER_ID = "user_ahmet"
PEER_ID = "local_user"

# Renk kodlari
GREEN = "\033[92m"
BLUE = "\033[94m"
YELLOW = "\033[93m"
CYAN = "\033[96m"
RESET = "\033[0m"
BOLD = "\033[1m"

def make_message(text):
    return json.dumps({
        "type": "encrypted_message",
        "senderId": USER_ID,
        "recipientId": PEER_ID,
        "timestamp": int(time.time() * 1000),
        "envelope": text
    })

async def receive_messages(ws):
    """Gelen mesajlari dinle ve ekrana bas."""
    try:
        async for raw in ws:
            try:
                msg = json.loads(raw)
                msg_type = msg.get("type", "unknown")
                sender = msg.get("senderId", "?")
                if msg_type == "encrypted_message":
                    content = msg.get("envelope", "")
                    print(f"\n{BLUE}{BOLD}[GELEN]{RESET} {sender}: {content}")
                else:
                    print(f"\n{YELLOW}[SIGNAL]{RESET} {msg_type} from {sender}")
                print(f"{GREEN}> {RESET}", end="", flush=True)
            except json.JSONDecodeError:
                pass
    except websockets.ConnectionClosed:
        print(f"\n{YELLOW}Baglanti kapandi.{RESET}")

async def send_messages(ws):
    """Kullanicidan mesaj al ve gonder."""
    loop = asyncio.get_event_loop()
    while True:
        try:
            text = await loop.run_in_executor(None, lambda: input(f"{GREEN}> {RESET}"))
            if not text.strip():
                continue
            if text.strip().lower() in ("quit", "exit", "q"):
                print(f"{YELLOW}Cikiliyor...{RESET}")
                await ws.close()
                break
            await ws.send(make_message(text.strip()))
            print(f"{CYAN}[GONDERILDI]{RESET} {text.strip()}")
        except (EOFError, KeyboardInterrupt):
            print(f"\n{YELLOW}Cikiliyor...{RESET}")
            await ws.close()
            break

async def auto_demo(ws):
    """Otomatik demo: sirayla mesaj gonder."""
    messages = [
        "Selam! Ben Ahmet, nasil gidiyor?",
        "SecureChat uzerinden yaziyorum, sifreleme harika!",
        "Bu mesajlar P2P signaling ile iletiliyor.",
        "Gercek zamanlida mesajlasma calisiyor mu?",
        "Harika, gorusuruz!",
    ]
    await asyncio.sleep(2)
    for i, text in enumerate(messages):
        await ws.send(make_message(text))
        print(f"{CYAN}[{i+1}/{len(messages)}]{RESET} Gonderildi: {text}")
        await asyncio.sleep(3)

    print(f"\n{GREEN}{BOLD}=== Demo tamamlandi! ==={RESET}")
    print(f"Emulator ekraninda {len(messages)} yeni mesaj gormelisiniz.")
    print(f"\nInteraktif moda geciliyor. Mesaj yazip Enter'a basin (cikis: q)\n")

    # Interaktif moda gec
    await send_messages(ws)

async def main():
    mode = "auto"
    if len(sys.argv) > 1 and sys.argv[1] == "--interactive":
        mode = "interactive"

    url = f"{SERVER_URL}?userId={USER_ID}"
    print(f"{BOLD}=== SecureChat Kullanici Simulatoru ==={RESET}")
    print(f"Kullanici: {CYAN}{USER_ID}{RESET}")
    print(f"Hedef:     {CYAN}{PEER_ID}{RESET}")
    print(f"Sunucu:    {CYAN}{SERVER_URL}{RESET}")
    print(f"Mod:       {CYAN}{mode}{RESET}")
    print()

    try:
        async with websockets.connect(url) as ws:
            print(f"{GREEN}{BOLD}Baglanti kuruldu!{RESET}\n")

            # Gelen mesajlari ayri task'ta dinle
            receiver = asyncio.create_task(receive_messages(ws))

            if mode == "auto":
                await auto_demo(ws)
            else:
                print("Mesaj yazip Enter'a basin (cikis: q)\n")
                await send_messages(ws)

            receiver.cancel()
    except ConnectionRefusedError:
        print(f"\n{YELLOW}HATA: Signaling sunucusu calismiyor!{RESET}")
        print("Once sunucuyu baslatin: ./gradlew :signaling-server:run")
    except Exception as e:
        print(f"\n{YELLOW}HATA: {e}{RESET}")

if __name__ == "__main__":
    asyncio.run(main())
