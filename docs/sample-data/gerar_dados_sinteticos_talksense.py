#!/usr/bin/env python3
"""
TalkSense - Compreensão inteligente das chamadas
Gerador de Dados Sintéticos para Analytics de Agente de Voz (Setor Financeiro)

Gera dados sintéticos no formato Event Hub (JSON) para simulação completa do Plano B:
- Eventos JSON (Event Hub format)
- CSVs para Eventhouse (tabelas KQL)
- Dados anonimizados (sem informações reais)
- Case genérico de banco digital

Arquitetura: Event Hub → Fabric Eventstream → Eventhouse → Power BI
"""

import json
import random
import argparse
import csv
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Dict, Any
import hashlib

# ============================================================================
# Configuração
# ============================================================================

SEED = 42
OUTPUT_DIR = Path("output")

# Dados fictícios anonimizados (banco digital genérico)
BANK_NAME = "DigitalBank"  # Nome anonimizado
PRODUCT_NAMES = {
    "investimentos": "Investimentos Digitais",
    "seguros": "Proteção 360",
    "cartoes": "Cartão Premium",
    "emprestimos": "Crédito Flex",
    "previdencia": "Futuro Seguro"
}

INTENTS = [
    "saldo", "extrato", "investimentos", "aplicacao", "resgate",
    "seguros", "cotacao_seguro", "sinistro", "cartao_bloqueio",
    "cartao_desbloqueio", "fatura", "limite", "emprestimo_simulacao",
    "emprestimo_contratacao", "transferencia_ted", "transferencia_pix",
    "pagamento_boleto", "previdencia", "saque_exterior", "cambio"
]

EVENT_TYPES = {
    "no_comprehension": "Não compreendeu a fala",
    "knowledge_gap": "Falta de conhecimento",
    "agent_requested": "Pedido de atendente humano",
    "returned_to_ura": "Retorno ao menu URA",
    "barge_in": "Cliente interrompeu",
    "silence_timeout": "Silêncio do cliente",
    "system_error": "Erro técnico",
    "conversation_ended": "Conversa encerrada"
}

OUTCOMES = [
    "resolved_by_ai",
    "transferred_to_agent",
    "customer_hangup",
    "system_timeout"
]

CHANNELS = ["phone", "whatsapp", "chat"]
SEGMENTS = ["Premium", "Standard", "Basic", "VIP"]
QUEUES = ["atendimento_principal", "investimentos", "seguros", "credito"]

# ============================================================================
# Funções Auxiliares
# ============================================================================

def gerar_id_anonimo(base: str) -> str:
    """Gera ID anonimizado com hash SHA256"""
    return hashlib.sha256(base.encode()).hexdigest()[:16]

def gerar_timestamp(base_date: datetime, delta_seconds: int = 0) -> str:
    """Gera timestamp ISO 8601 UTC"""
    return (base_date + timedelta(seconds=delta_seconds)).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"

def gerar_conversation_id(index: int, date: datetime) -> str:
    """Gera ID de conversa único"""
    return f"conv-{date.strftime('%Y%m%d')}-{index:06d}"

def escolher_com_peso(opcoes: List[str], pesos: List[float]) -> str:
    """Escolhe opção com probabilidade ponderada"""
    return random.choices(opcoes, weights=pesos, k=1)[0]

# ============================================================================
# Geradores de Eventos (Formato Event Hub)
# ============================================================================

def gerar_evento_conversation_started(
    conversation_id: str,
    timestamp: str,
    customer_segment: str,
    initial_intent: str,
    channel: str,
    queue: str
) -> Dict[str, Any]:
    """Gera evento: conversation_started"""
    session_id = f"sess-{gerar_id_anonimo(conversation_id)}"
    customer_id_anon = gerar_id_anonimo(f"customer-{random.randint(1000, 9999)}")
    
    return {
        "eventType": "conversation_started",
        "timestamp": timestamp,
        "conversationId": conversation_id,
        "payload": {
            "sessionId": session_id,
            "channel": channel,
            "customerIdAnon": customer_id_anon,
            "customerSegment": customer_segment,
            "initialIntent": initial_intent,
            "originQueue": queue,
            "metadata": {
                "region": random.choice(["BR-SP", "BR-RJ", "BR-MG", "BR-RS"]),
                "languageCode": "pt-BR"
            }
        }
    }

def gerar_evento_turn_completed(
    conversation_id: str,
    timestamp: str,
    turn_index: int,
    intent: str,
    latency_ms: int
) -> Dict[str, Any]:
    """Gera evento: turn_completed"""
    sentiments = ["positive", "neutral", "negative"]
    sentiment = escolher_com_peso(sentiments, [0.4, 0.5, 0.1])
    sentiment_scores = {"positive": 0.8, "neutral": 0.5, "negative": 0.2}
    
    responses = {
        "saldo": f"Seu saldo atual é R$ {random.randint(100, 50000):.2f}.",
        "extrato": "Consultando seu extrato dos últimos 30 dias.",
        "investimentos": f"Você possui R$ {random.randint(1000, 100000):.2f} investidos.",
        "transferencia_pix": "Transferência PIX realizada com sucesso.",
        "cartao_bloqueio": "Cartão bloqueado por segurança.",
    }
    
    return {
        "eventType": "turn_completed",
        "timestamp": timestamp,
        "conversationId": conversation_id,
        "payload": {
            "turnIndex": turn_index,
            "userUtterance": "[MASKED]",  # PII mascarado
            "agentResponse": responses.get(intent, f"Processando sua solicitação sobre {intent}."),
            "intent": intent,
            "intentConfidence": round(random.uniform(0.75, 0.99), 2),
            "entities": [],
            "sentiment": {
                "overall": sentiment,
                "score": sentiment_scores[sentiment] + random.uniform(-0.1, 0.1)
            },
            "latencyMs": latency_ms,
            "ttsEnabled": random.choice([True, False]),
            "bargeInDetected": random.choice([True, False]) if random.random() < 0.1 else False
        }
    }

def gerar_evento_conversation_event(
    conversation_id: str,
    timestamp: str,
    event_name: str,
    turn_index: int = None
) -> Dict[str, Any]:
    """Gera evento: conversation_event"""
    categories = {
        "no_comprehension": "error",
        "knowledge_gap": "error",
        "agent_requested": "handoff",
        "returned_to_ura": "navigation",
        "barge_in": "interaction",
        "silence_timeout": "interaction",
        "system_error": "error",
        "conversation_ended": "completion"
    }
    
    details = {}
    if event_name == "agent_requested":
        details = {"reason": random.choice(["complex_query", "customer_request", "escalation"])}
    elif event_name == "system_error":
        details = {"errorType": random.choice(["timeout", "api_failure", "network_error"])}
    elif event_name == "conversation_ended":
        details = {
            "outcome": escolher_com_peso(OUTCOMES, [0.7, 0.15, 0.10, 0.05]),
            "durationSeconds": random.randint(60, 600),
            "totalTurns": random.randint(2, 15)
        }
    
    return {
        "eventType": "conversation_event",
        "timestamp": timestamp,
        "conversationId": conversation_id,
        "payload": {
            "eventName": event_name,
            "eventCategory": categories[event_name],
            "turnIndex": turn_index,
            "details": details
        }
    }

def gerar_evento_csat_received(
    conversation_id: str,
    timestamp: str
) -> Dict[str, Any]:
    """Gera evento: csat_received"""
    score = escolher_com_peso([5, 4, 3, 2, 1], [0.4, 0.3, 0.15, 0.10, 0.05])
    comments = {
        5: "Excelente atendimento!",
        4: "Muito bom, rápido.",
        3: "Atendeu, mas poderia ser melhor.",
        2: "Demorado.",
        1: "Não resolveu meu problema."
    }
    
    return {
        "eventType": "csat_received",
        "timestamp": timestamp,
        "conversationId": conversation_id,
        "payload": {
            "score": score,
            "scale": "1-5",
            "comment": comments[score] if random.random() < 0.6 else "",
            "collectedVia": random.choice(["post_call_ivr", "email", "sms"])
        }
    }

# ============================================================================
# Gerador Principal
# ============================================================================

def gerar_conversa(
    index: int,
    base_date: datetime
) -> tuple[List[Dict[str, Any]], Dict[str, Any], List[Dict[str, Any]], List[Dict[str, Any]], Dict[str, Any]]:
    """
    Gera uma conversa completa com eventos, retornando:
    - Lista de eventos JSON (Event Hub)
    - Registro de conversa (CSV)
    - Lista de turnos (CSV)
    - Lista de eventos (CSV)
    - Registro de CSAT (CSV, opcional)
    """
    
    conversation_id = gerar_conversation_id(index, base_date)
    segment = random.choice(SEGMENTS)
    channel = escolher_com_peso(CHANNELS, [0.7, 0.2, 0.1])
    queue = random.choice(QUEUES)
    initial_intent = random.choice(INTENTS)
    
    # Timestamp inicial
    start_time = base_date + timedelta(
        hours=random.randint(8, 20),
        minutes=random.randint(0, 59),
        seconds=random.randint(0, 59)
    )
    
    eventos_json = []
    turnos_csv = []
    eventos_csv = []
    
    # 1. Evento: conversation_started
    evento_start = gerar_evento_conversation_started(
        conversation_id, gerar_timestamp(start_time),
        segment, initial_intent, channel, queue
    )
    eventos_json.append(evento_start)
    
    # 2. Turnos (2 a 10)
    num_turns = random.randint(2, 10)
    current_time = start_time
    
    for turn_idx in range(1, num_turns + 1):
        current_time += timedelta(seconds=random.randint(3, 15))
        intent = initial_intent if turn_idx == 1 else random.choice(INTENTS)
        latency = random.randint(500, 3000)
        
        evento_turn = gerar_evento_turn_completed(
            conversation_id, gerar_timestamp(current_time),
            turn_idx, intent, latency
        )
        eventos_json.append(evento_turn)
        
        # Registro CSV do turno
        turnos_csv.append({
            "conversationId": conversation_id,
            "timestamp": gerar_timestamp(current_time),
            "turnIndex": turn_idx,
            "userUtterance": "[MASKED]",
            "agentResponse": evento_turn["payload"]["agentResponse"],
            "intent": intent,
            "intentConfidence": evento_turn["payload"]["intentConfidence"],
            "sentimentOverall": evento_turn["payload"]["sentiment"]["overall"],
            "sentimentScore": evento_turn["payload"]["sentiment"]["score"],
            "latencyMs": latency,
            "ttsEnabled": evento_turn["payload"]["ttsEnabled"],
            "bargeInDetected": evento_turn["payload"]["bargeInDetected"]
        })
    
    # 3. Eventos especiais (probabilísticos)
    if random.random() < 0.15:  # 15% de chance de não compreensão
        current_time += timedelta(seconds=random.randint(2, 8))
        evento_error = gerar_evento_conversation_event(
            conversation_id, gerar_timestamp(current_time),
            random.choice(["no_comprehension", "knowledge_gap"]),
            random.randint(2, num_turns)
        )
        eventos_json.append(evento_error)
        eventos_csv.append({
            "conversationId": conversation_id,
            "timestamp": gerar_timestamp(current_time),
            "eventName": evento_error["payload"]["eventName"],
            "eventCategory": evento_error["payload"]["eventCategory"],
            "turnIndex": evento_error["payload"]["turnIndex"]
        })
    
    if random.random() < 0.12:  # 12% pedido de atendente
        current_time += timedelta(seconds=random.randint(5, 20))
        evento_agent = gerar_evento_conversation_event(
            conversation_id, gerar_timestamp(current_time),
            "agent_requested", random.randint(2, num_turns)
        )
        eventos_json.append(evento_agent)
        eventos_csv.append({
            "conversationId": conversation_id,
            "timestamp": gerar_timestamp(current_time),
            "eventName": "agent_requested",
            "eventCategory": "handoff",
            "turnIndex": evento_agent["payload"]["turnIndex"]
        })
    
    # 4. Evento: conversation_ended
    current_time += timedelta(seconds=random.randint(5, 30))
    outcome = escolher_com_peso(OUTCOMES, [0.70, 0.15, 0.10, 0.05])
    duration = int((current_time - start_time).total_seconds())
    
    evento_end = gerar_evento_conversation_event(
        conversation_id, gerar_timestamp(current_time),
        "conversation_ended"
    )
    evento_end["payload"]["details"] = {
        "outcome": outcome,
        "durationSeconds": duration,
        "totalTurns": num_turns
    }
    eventos_json.append(evento_end)
    eventos_csv.append({
        "conversationId": conversation_id,
        "timestamp": gerar_timestamp(current_time),
        "eventName": "conversation_ended",
        "eventCategory": "completion",
        "turnIndex": None
    })
    
    # 5. Registro de conversa (CSV)
    conversa_csv = {
        "conversationId": conversation_id,
        "timestamp": gerar_timestamp(start_time),
        "sessionId": evento_start["payload"]["sessionId"],
        "channel": channel,
        "customerIdAnon": evento_start["payload"]["customerIdAnon"],
        "customerSegment": segment,
        "initialIntent": initial_intent,
        "originQueue": queue,
        "outcome": outcome,
        "durationSeconds": duration,
        "totalTurns": num_turns
    }
    
    # 6. CSAT (60% de chance)
    csat_csv = None
    if random.random() < 0.6:
        current_time += timedelta(minutes=random.randint(5, 30))
        evento_csat = gerar_evento_csat_received(
            conversation_id, gerar_timestamp(current_time)
        )
        eventos_json.append(evento_csat)
        
        csat_csv = {
            "conversationId": conversation_id,
            "timestamp": gerar_timestamp(current_time),
            "score": evento_csat["payload"]["score"],
            "scale": evento_csat["payload"]["scale"],
            "comment": evento_csat["payload"]["comment"],
            "collectedVia": evento_csat["payload"]["collectedVia"]
        }
    
    return eventos_json, conversa_csv, turnos_csv, eventos_csv, csat_csv

# ============================================================================
# Main
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="Gerar dados sintéticos TalkSense")
    parser.add_argument("--conversas", type=int, default=100, help="Número de conversas")
    parser.add_argument("--dias", type=int, default=30, help="Período em dias")
    parser.add_argument("--seed", type=int, default=SEED, help="Seed aleatória")
    args = parser.parse_args()
    
    random.seed(args.seed)
    OUTPUT_DIR.mkdir(exist_ok=True)
    
    print(f"\nTalkSense - Gerador de Dados Sintéticos")
    print(f"   Compreensão inteligente das chamadas\n")
    print(f"Configuração:")
    print(f"   - Conversas: {args.conversas}")
    print(f"   - Período: {args.dias} dias")
    print(f"   - Seed: {args.seed}\n")
    
    # Data base
    end_date = datetime.now()
    start_date = end_date - timedelta(days=args.dias)
    
    # Listas para acumular dados
    todos_eventos_json = []
    conversas_csv = []
    turnos_csv = []
    eventos_csv = []
    csat_csv = []
    
    # Gerar conversas
    print("⚙️  Gerando conversas...")
    for i in range(args.conversas):
        # Data aleatória no período
        dias_offset = random.randint(0, args.dias - 1)
        data_conversa = start_date + timedelta(days=dias_offset)
        
        eventos, conversa, turnos, eventos_list, csat = gerar_conversa(i + 1, data_conversa)
        
        todos_eventos_json.extend(eventos)
        conversas_csv.append(conversa)
        turnos_csv.extend(turnos)
        eventos_csv.extend(eventos_list)
        if csat:
            csat_csv.append(csat)
        
        if (i + 1) % 50 == 0:
            print(f"   ✓ {i + 1}/{args.conversas} conversas geradas")
    
    print(f"\n✅ {args.conversas} conversas geradas!\n")
    
    # Salvar eventos JSON (formato Event Hub)
    print("💾 Salvando eventos JSON (Event Hub format)...")
    with open(OUTPUT_DIR / "eventhub_events.json", "w", encoding="utf-8") as f:
        json.dump(todos_eventos_json, f, ensure_ascii=False, indent=2)
    print(f"   - {len(todos_eventos_json)} eventos salvos em eventhub_events.json")
    
    # Salvar CSVs (formato Eventhouse)
    print("\nSalvando CSVs (Eventhouse format)...")
    
    # Conversations.csv
    with open(OUTPUT_DIR / "conversations.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=conversas_csv[0].keys())
        writer.writeheader()
        writer.writerows(conversas_csv)
    print(f"   ✓ conversations.csv ({len(conversas_csv)} registros)")
    
    # Turns.csv
    with open(OUTPUT_DIR / "turns.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=turnos_csv[0].keys())
        writer.writeheader()
        writer.writerows(turnos_csv)
    print(f"   ✓ turns.csv ({len(turnos_csv)} registros)")
    
    # Events.csv
    with open(OUTPUT_DIR / "events.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=eventos_csv[0].keys())
        writer.writeheader()
        writer.writerows(eventos_csv)
    print(f"   ✓ events.csv ({len(eventos_csv)} registros)")
    
    # CSAT.csv
    if csat_csv:
        with open(OUTPUT_DIR / "csat.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=csat_csv[0].keys())
            writer.writeheader()
            writer.writerows(csat_csv)
        print(f"   ✓ csat.csv ({len(csat_csv)} registros)")
    
    # Exemplo de evento único
    print("\n💾 Salvando evento de exemplo...")
    with open(OUTPUT_DIR / "event_sample.json", "w", encoding="utf-8") as f:
        json.dump(todos_eventos_json[0], f, ensure_ascii=False, indent=2)
    print("   - event_sample.json")
    
    print("\nGeração concluída!")
    print(f"\nArquivos gerados em: {OUTPUT_DIR.absolute()}")
    print("\nPróximos passos:")
    print("   1. Carregar CSVs no Eventhouse para testes")
    print("   2. Usar eventhub_events.json para simular envio ao Event Hub")
    print("   3. Conectar Power BI ao Eventhouse")
    print("   4. Validar as 9 métricas no dashboard\n")

if __name__ == "__main__":
    main()
