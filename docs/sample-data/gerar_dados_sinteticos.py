#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Gerador de dados sintéticos — Telemetria do Agente de Voz (Investimentos / Banco Inter).

Produz amostras APENAS para testar o dashboard do Power BI e validar quais colunas
o modelo precisa. NÃO usa dados reais de clientes. Somente biblioteca padrão do Python.

Saídas (em ./output):
  - conversations.csv   (grão = 1 atendimento)         -> FatoConversa
  - turns.csv           (grão = 1 turno / transcrição)  -> FatoTurno
  - events.csv          (grão = 1 evento de telemetria) -> FatoEvento
  - csat.csv            (grão = 1 resposta de pesquisa)  -> FatoCsat
  - dim_data.csv        (dimensão calendário)            -> DimData
  - conversation_sample.json  (1 documento Cosmos DB aninhado, exemplo)

Uso:
  python gerar_dados_sinteticos.py [--conversas 600] [--dias 30] [--seed 42]
"""

import argparse
import csv
import hashlib
import json
import os
import random
import uuid
from datetime import datetime, timedelta

# --------------------------------------------------------------------------------------
# Configuração de domínio (Investimentos) — baseada na base de conhecimento do agente
# --------------------------------------------------------------------------------------

# Intenções / acionamentos (métrica #4) com peso de ocorrência
INTENCOES = [
    # (chave, rótulo, categoria, subcategoria, peso)
    ("resgate_porquinho",      "Resgate do Meu Porquinho",            "Investimentos", "Meu Porquinho",            22),
    ("cdb_mais_limite",        "CDB Mais Limite",                      "Investimentos", "Limite de Crédito Investido", 16),
    ("tesouro_valor",          "Valor do Tesouro Direto",              "Investimentos", "Tesouro Direto",           12),
    ("tesouro_carteira",       "Tesouro não aparece na carteira",      "Investimentos", "Tesouro Direto",           10),
    ("como_investir",          "Como investir pelo app",               "Investimentos", "Geral",                     9),
    ("rendimento_porquinho",   "Rendimento do Porquinho",              "Investimentos", "Meu Porquinho",             8),
    ("portabilidade",          "Portabilidade de investimentos",       "Investimentos", "Portabilidade",             7),
    ("perfil_investidor",      "Perfil de investidor",                 "Investimentos", "Perfil",                    6),
    ("aluguel_ativos_intl",    "Aluguel de ativos internacionais",     "Investimentos", "Inter Securities",          5),
    ("outros",                 "Outros assuntos de investimentos",     "Investimentos", "Geral",                     5),
]

# Falas do cliente por intenção (para a transcrição)
FALA_CLIENTE = {
    "resgate_porquinho":    ["Oi, resgatei meu Porquinho e o dinheiro ainda não caiu na conta.",
                             "Fiz um resgate do CDB Mais Limite e não recebi o valor.",
                             "Meu resgate do Porquinho por Objetivos está demorando, é normal?"],
    "cdb_mais_limite":      ["Não estou conseguindo investir no CDB Mais Limite.",
                             "Por que meu limite não aumentou depois que investi no CDB Mais Limite?",
                             "Qual a diferença entre CDB Mais Limite e Poupança Mais Limite?"],
    "tesouro_valor":        ["O valor do meu Tesouro Direto está diferente do que apliquei.",
                             "Meu Tesouro Selic aparece com valor menor, o que aconteceu?"],
    "tesouro_carteira":     ["Comprei Tesouro Direto e não está aparecendo na carteira.",
                             "Meu título do Tesouro sumiu da carteira de investimentos."],
    "como_investir":        ["Como eu faço para investir pelo aplicativo?",
                             "Quais tipos de investimento tem disponível no Inter?"],
    "rendimento_porquinho": ["Quanto meu Porquinho está rendendo?",
                             "O rendimento do meu Porquinho parece baixo esse mês."],
    "portabilidade":        ["Quero trazer meus investimentos de outra corretora pro Inter.",
                             "Como funciona a portabilidade de investimentos?"],
    "perfil_investidor":    ["Preciso refazer meu perfil de investidor.",
                             "Onde eu atualizo o perfil de investidor?"],
    "aluguel_ativos_intl":  ["Como funciona o aluguel de ativos internacionais?",
                             "Quero ativar o empréstimo de ações na Inter Securities."],
    "outros":               ["Tenho uma dúvida sobre investimentos.",
                             "Queria entender melhor uns produtos de investimento."],
}

# Respostas informativas da IA por intenção (resumo da KB)
FALA_IA = {
    "resgate_porquinho":    ["Cada Porquinho tem uma regra de resgate. No CDB Dia a Dia, pedidos até 21h55 caem no mesmo dia; após 22h entram para o próximo dia útil.",
                             "No CDB Mais Limite o valor cai em até 15 minutos, desde que não esteja comprometido com fatura ou garantias. Você pagou a fatura em outro banco?"],
    "cdb_mais_limite":      ["Para investir no CDB Mais Limite o cartão precisa estar ativo e sem fatura em atraso. As aplicações ficam disponíveis das 6h às 21h.",
                             "O CDB Mais Limite converte o valor investido em limite de crédito; a Poupança Mais Limite permite escolher quanto do valor vira limite."],
    "tesouro_valor":        ["O valor do Tesouro pode variar pela marcação a mercado, que reflete o preço do título antes do vencimento. É normal e pode subir ou cair."],
    "tesouro_carteira":     ["Após a compra, o Tesouro pode levar até 2 dias úteis para aparecer na carteira. Você também pode conferir no Portal do Investidor da B3."],
    "como_investir":        ["No Super App, acesse o menu Investimentos e escolha o produto: CDB, LCI, LCA, Tesouro Direto, fundos, previdência ou Home Broker."],
    "rendimento_porquinho": ["O Porquinho rende todo mês conforme o produto. No CDB Dia a Dia o rendimento começa após 1 dia útil aplicado."],
    "portabilidade":        ["A portabilidade traz seus investimentos de outra instituição. Acesse Investimentos > Portabilidade para ver os tipos disponíveis."],
    "perfil_investidor":    ["Você atualiza o perfil em Investimentos > Configurações > Perfil de investidor. Ele é necessário para novas aplicações."],
    "aluguel_ativos_intl":  ["No aluguel de ativos, suas ações na Inter Securities são emprestadas e você recebe remuneração, continuando dono e podendo vender a qualquer momento."],
    "outros":               ["Posso te ajudar com informações sobre investimentos do Inter. Sobre qual produto você quer saber?"],
}

# Deeplinks / artigos de KB por intenção (para kb_artigos)
KB_ARTIGO = {
    "resgate_porquinho": "eb3fc5d3-494f-464d-ae84-730ec7d183af",
    "cdb_mais_limite":   "d86d4c95-cffb-4ea0-9b74-46bd8e2aed98",
    "tesouro_valor":     "6997bd2e-6f84-4434-bb6a-65e516acca03",
    "tesouro_carteira":  "16662d73-9190-4a06-a50b-2bcc475371cf",
    "aluguel_ativos_intl": "45c5f572-586c-4d8d-a6af-5d69189223f3",
}

# Desfechos (métricas #1,#5,#6,#7,#8) com peso
DESFECHOS = [
    ("retido_ia",                     58),  # IA resolveu (não transbordou)
    ("transbordo_sem_conhecimento",   10),  # #5
    ("transbordo_nao_compreensao",     9),  # #5
    ("transbordo_pedido_atendente",    8),  # #7
    ("transbordo_erro",                4),  # #8
    ("retorno_menu_ura",               7),  # #6
    ("abandono",                       4),
]

FILA_TRANSBORDO = "CX_CRL_Geral_Investimentos"
DIAS_SEMANA_PT = ["Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado", "Domingo"]
MESES_PT = ["Jan", "Fev", "Mar", "Abr", "Mai", "Jun", "Jul", "Ago", "Set", "Out", "Nov", "Dez"]

COMENTARIOS_CSAT = {
    5: ["Atendimento excelente, resolveu rápido!", "Muito bom, tirou minha dúvida na hora."],
    4: ["Bom atendimento, só demorou um pouco.", "Gostei, ajudou bastante."],
    3: ["Foi ok, mas tive que repetir a pergunta.", "Resolveu em parte."],
    2: ["Não entendeu direito o que eu queria.", "Precisei falar com um atendente depois."],
    1: ["Não resolveu meu problema.", "Muito confuso, não me ajudou."],
}


def weighted_choice(pairs):
    itens = [p[0] for p in pairs]
    pesos = [p[-1] for p in pairs]
    return random.choices(itens, weights=pesos, k=1)[0]


def intencao_meta(chave):
    for c in INTENCOES:
        if c[0] == chave:
            return c
    return INTENCOES[0]


def anon_cliente(n):
    """id anonimizado determinístico (hash) — simula HMAC do CPF."""
    h = hashlib.sha256(f"cpf-sintetico-{n}".encode()).hexdigest()[:10]
    return f"CLI-{h}"


def sentimento_por_desfecho(desfecho):
    """Retorna (rótulo, score) coerente com o desfecho."""
    if desfecho == "retido_ia":
        s = round(random.uniform(0.1, 0.9), 2)
    elif desfecho in ("transbordo_pedido_atendente", "retorno_menu_ura"):
        s = round(random.uniform(-0.3, 0.4), 2)
    elif desfecho == "abandono":
        s = round(random.uniform(-0.6, 0.1), 2)
    else:  # transbordos por falha
        s = round(random.uniform(-0.9, -0.1), 2)
    rotulo = "positivo" if s > 0.2 else ("negativo" if s < -0.2 else "neutro")
    return rotulo, s


def nota_csat_por_desfecho(desfecho):
    if desfecho == "retido_ia":
        return random.choices([5, 4, 3], weights=[55, 30, 15])[0]
    if desfecho in ("retorno_menu_ura", "transbordo_pedido_atendente"):
        return random.choices([4, 3, 2], weights=[25, 45, 30])[0]
    if desfecho == "transbordo_erro":
        return random.choices([2, 1], weights=[45, 55])[0]
    if desfecho.startswith("transbordo"):
        return random.choices([3, 2, 1], weights=[30, 45, 25])[0]
    return random.choices([3, 2, 1], weights=[30, 35, 35])[0]  # abandono


def build_dim_data(inicio, dias):
    linhas = []
    for i in range(dias + 1):
        d = (inicio + timedelta(days=i)).date()
        linhas.append({
            "dataKey": int(d.strftime("%Y%m%d")),
            "data": d.isoformat(),
            "ano": d.year,
            "mes": d.month,
            "nome_mes": MESES_PT[d.month - 1],
            "dia": d.day,
            "dia_semana": d.weekday() + 1,
            "nome_dia_semana": DIAS_SEMANA_PT[d.weekday()],
            "semana_ano": int(d.strftime("%W")),
            "fim_de_semana": 1 if d.weekday() >= 5 else 0,
        })
    return linhas


def gerar(conversas, dias, seed):
    random.seed(seed)
    base_dir = os.path.dirname(os.path.abspath(__file__))
    out_dir = os.path.join(base_dir, "output")
    os.makedirs(out_dir, exist_ok=True)

    fim = datetime(2026, 6, 30, 23, 59, 0)
    inicio = fim - timedelta(days=dias)
    n_clientes = max(50, conversas // 3)  # alguns clientes repetem (para "quais clientes")

    conv_rows, turn_rows, event_rows, csat_rows = [], [], [], []
    primeiro_doc_json = None

    for _ in range(conversas):
        cid = str(uuid.uuid4())
        sid = "sess-" + uuid.uuid4().hex[:12]
        cliente = anon_cliente(random.randint(1, n_clientes))
        intent_key, intent_label, categoria, subcategoria, _ = intencao_meta(weighted_choice(INTENCOES))
        desfecho = weighted_choice(DESFECHOS)

        inicio_ts = inicio + timedelta(
            days=random.randint(0, dias),
            hours=random.choices(range(24), weights=[1,1,1,1,1,2,3,5,7,8,9,9,8,8,9,9,8,7,6,5,4,3,2,1])[0],
            minutes=random.randint(0, 59), seconds=random.randint(0, 59),
        )

        qtd_turnos = random.randint(4, 18)
        # duração média por turno 6-14s
        tma = sum(random.randint(6, 14) for _ in range(qtd_turnos))
        fim_ts = inicio_ts + timedelta(seconds=tma)

        transferido = desfecho.startswith("transbordo")
        retido = 0 if transferido else 1
        motivo = {
            "transbordo_sem_conhecimento": "sem_conhecimento",
            "transbordo_nao_compreensao": "nao_compreensao",
            "transbordo_pedido_atendente": "pedido_atendente",
            "transbordo_erro": "erro",
        }.get(desfecho, "")
        retornou_ura = 1 if desfecho == "retorno_menu_ura" else 0
        gatilho_ura = ("digitou_0" if random.random() < 0.6 else "fala_voltar") if retornou_ura else ""
        pediu_atendente = 1 if desfecho == "transbordo_pedido_atendente" else (1 if random.random() < 0.03 else 0)
        teve_erro = 1 if desfecho == "transbordo_erro" else (1 if random.random() < 0.02 else 0)
        tipo_erro = random.choice(["timeout_asr", "falha_tts", "erro_integracao", "instabilidade"]) if teve_erro else ""
        codigo_erro = ("E" + str(random.randint(500, 599))) if teve_erro else ""

        interrupcoes = random.choices([0, 1, 2, 3], weights=[55, 25, 13, 7])[0]
        kb_hit = 0 if desfecho == "transbordo_sem_conhecimento" else (1 if random.random() < 0.9 else 0)
        kb_artigos = KB_ARTIGO.get(intent_key, "") if kb_hit else ""

        sent_rotulo, sent_score = sentimento_por_desfecho(desfecho)
        sent_inicio = round(min(0.9, max(-0.9, sent_score + random.uniform(0.1, 0.4))), 2)
        sent_fim = round(min(0.95, max(-0.95, sent_score - random.uniform(0.0, 0.3))), 2)

        respondeu_csat = 1 if random.random() < 0.38 else 0
        nota = nota_csat_por_desfecho(desfecho) if respondeu_csat else ""

        # ---------- turnos (transcrição + latência da IA => TMR) ----------
        latencias_ia = []
        t_cursor = inicio_ts
        idx = 0
        # saudação + opção de menu URA (aderência ao escopo)
        turn_rows.append(_turn(cid, idx, t_cursor, "ia",
            "Oi! Sou a assistente de investimentos do Inter. A qualquer momento, diga ou digite 0 para voltar ao menu.",
            "", "", _lat(latencias_ia), "positivo", 0.6, 0, "", 0)); idx += 1
        t_cursor += timedelta(seconds=random.randint(5, 9))

        falas_c = FALA_CLIENTE[intent_key]
        falas_ia = FALA_IA[intent_key]
        pares = max(2, (qtd_turnos - 1) // 2)
        for p in range(pares):
            # turno do cliente
            texto_c = random.choice(falas_c) if p == 0 else random.choice(
                ["Entendi. E nesse caso?", "Certo. Pode me explicar melhor?", "Ok, e o que eu faço agora?",
                 "Ainda não resolveu.", "Tá, e sobre o prazo?"])
            interrompeu = 1 if (interrupcoes > 0 and p > 0 and random.random() < 0.3) else 0
            conf = round(random.uniform(0.35, 0.66), 2) if motivo == "nao_compreensao" and p == pares - 1 else round(random.uniform(0.72, 0.99), 2)
            turn_rows.append(_turn(cid, idx, t_cursor, "cliente", texto_c, intent_key, "", "",
                                   sent_rotulo, round(sent_score + random.uniform(-0.2, 0.2), 2), interrompeu, "", 0)); idx += 1
            t_cursor += timedelta(seconds=random.randint(4, 9))

            # turno da IA
            fallback = 1 if (motivo in ("nao_compreensao", "sem_conhecimento") and p == pares - 1) else 0
            if fallback:
                texto_ia = "Desculpe, não consegui entender completamente. Só um momento que vou te transferir para um atendente."
                kb_id = ""
            else:
                texto_ia = random.choice(falas_ia)
                kb_id = KB_ARTIGO.get(intent_key, "") if kb_hit else ""
            turn_rows.append(_turn(cid, idx, t_cursor, "ia", texto_ia, "", "", _lat(latencias_ia),
                                   sent_rotulo, round(sent_score + random.uniform(-0.1, 0.2), 2), 0, kb_id, fallback)); idx += 1
            t_cursor += timedelta(seconds=random.randint(6, 12))

        # turno final conforme desfecho
        if transferido:
            turn_rows.append(_turn(cid, idx, t_cursor, "ia",
                "Só um momento que vou te transferir para um atendente.", "", "", _lat(latencias_ia),
                "neutro", -0.1, 0, "", 0)); idx += 1
        elif retornou_ura:
            turn_rows.append(_turn(cid, idx, t_cursor, "ia",
                "Sem problemas! Vou te levar de volta ao menu de opções de investimentos.", "", "", _lat(latencias_ia),
                "neutro", 0.1, 0, "", 0)); idx += 1

        qtd_turnos_real = idx
        lat_media = round(sum(latencias_ia) / len(latencias_ia)) if latencias_ia else 0
        lat_p95 = _p95(latencias_ia)

        # ---------- eventos (funil + erros) ----------
        event_rows.append(_evt(cid, inicio_ts, "session_start", "", "", "", "", "info"))
        for a in range(2):
            event_rows.append(_evt(cid, inicio_ts + timedelta(seconds=6 + a * 8), "nlu_intent", intent_key,
                                   random.randint(120, 480), "", "", "info"))
        if kb_hit:
            event_rows.append(_evt(cid, inicio_ts + timedelta(seconds=10), "kb_query", "hit", random.randint(80, 400), "", "", "info"))
        if teve_erro:
            event_rows.append(_evt(cid, inicio_ts + timedelta(seconds=tma - 5), "error", tipo_erro, "",
                                   codigo_erro, f"Falha: {tipo_erro}", "error"))
        if retornou_ura:
            event_rows.append(_evt(cid, fim_ts, "ura_return", gatilho_ura, "", "", "", "info"))
        if pediu_atendente:
            event_rows.append(_evt(cid, fim_ts - timedelta(seconds=4), "agent_requested", "", "", "", "", "info"))
        if transferido:
            event_rows.append(_evt(cid, fim_ts, "transfer_completed", motivo, "", "", "", "info"))
        event_rows.append(_evt(cid, fim_ts, "session_end", desfecho, "", "", "", "info"))
        if respondeu_csat:
            event_rows.append(_evt(cid, fim_ts + timedelta(minutes=1), "csat_response", str(nota), "", "", "", "info"))

        # ---------- csat ----------
        if respondeu_csat:
            csat_rows.append({
                "csatId": "csat-" + uuid.uuid4().hex[:12],
                "conversationId": cid,
                "id_cliente_anon": cliente,
                "nota_csat": nota,
                "comentario_csat": random.choice(COMENTARIOS_CSAT[nota]),
                "ts": (fim_ts + timedelta(minutes=1)).isoformat(),
                "canal_pesquisa": random.choice(["ura_pos_call", "sms", "push_app"]),
            })

        # ---------- linha da conversa (fato) ----------
        conv = {
            "conversationId": cid,
            "sessionId": sid,
            "id_cliente_anon": cliente,
            "segmento": "PF Digital",
            "canal": "voz",
            "inicio_ts": inicio_ts.isoformat(),
            "fim_ts": fim_ts.isoformat(),
            "data": inicio_ts.date().isoformat(),
            "dataKey": int(inicio_ts.strftime("%Y%m%d")),
            "hora": inicio_ts.hour,
            "dia_semana": DIAS_SEMANA_PT[inicio_ts.weekday()],
            "tempo_atendimento_seg": tma,
            "qtd_turnos": qtd_turnos_real,
            "qtd_interrupcoes": interrupcoes,
            "latencia_media_ms": lat_media,
            "latencia_p95_ms": lat_p95,
            "desfecho": desfecho,
            "retido_pela_ia": retido,
            "transferido_humano": 1 if transferido else 0,
            "motivo_transbordo": motivo,
            "fila_transbordo": FILA_TRANSBORDO if transferido else "",
            "retornou_menu_ura": retornou_ura,
            "gatilho_retorno_ura": gatilho_ura,
            "pediu_atendente": pediu_atendente,
            "teve_erro": teve_erro,
            "tipo_erro": tipo_erro,
            "codigo_erro": codigo_erro,
            "intencao_primaria": intent_key,
            "intencao_rotulo": intent_label,
            "categoria_intencao": categoria,
            "subcategoria_intencao": subcategoria,
            "kb_hit": kb_hit,
            "kb_artigos": kb_artigos,
            "nota_csat": nota,
            "respondeu_csat": respondeu_csat,
            "sentimento_geral": sent_rotulo,
            "sentimento_score": sent_score,
            "sentimento_inicio": sent_inicio,
            "sentimento_fim": sent_fim,
            "flag_precisao": 1 if (retido and random.random() < 0.92) else (0 if random.random() < 0.5 else 1),
            "flag_compreensao": 0 if motivo == "nao_compreensao" else 1,
            "flag_alucinacao": 1 if random.random() < 0.03 else 0,
            "flag_cobertura": kb_hit,
            "usou_desambiguacao": 1 if random.random() < 0.2 else 0,
            "score_aderencia_persona": round(random.uniform(0.8, 1.0), 2),
            "transcricao_disponivel": 1,
            "url_gravacao": f"https://storage.local/gravacoes/{cid}.wav",
        }
        conv_rows.append(conv)

        if primeiro_doc_json is None:
            primeiro_doc_json = _doc_json(conv, [r for r in turn_rows if r["conversationId"] == cid],
                                          [r for r in event_rows if r["conversationId"] == cid],
                                          [r for r in csat_rows if r["conversationId"] == cid])

    # ---------- escrita ----------
    _write_csv(os.path.join(out_dir, "conversations.csv"), conv_rows)
    _write_csv(os.path.join(out_dir, "turns.csv"), turn_rows)
    _write_csv(os.path.join(out_dir, "events.csv"), event_rows)
    _write_csv(os.path.join(out_dir, "csat.csv"), csat_rows)
    _write_csv(os.path.join(out_dir, "dim_data.csv"), build_dim_data(inicio, dias))
    with open(os.path.join(out_dir, "conversation_sample.json"), "w", encoding="utf-8") as f:
        json.dump(primeiro_doc_json, f, ensure_ascii=False, indent=2)

    print(f"OK -> {out_dir}")
    print(f"  conversations.csv : {len(conv_rows)} linhas")
    print(f"  turns.csv         : {len(turn_rows)} linhas")
    print(f"  events.csv        : {len(event_rows)} linhas")
    print(f"  csat.csv          : {len(csat_rows)} linhas")
    print(f"  dim_data.csv      : {dias + 1} linhas")
    _resumo(conv_rows)


# --------------------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------------------

def _lat(acc):
    """Latência de resposta da IA (ms) — feed do TMR. Acumula para média/p95."""
    val = int(random.gauss(780, 260))
    if random.random() < 0.05:
        val = int(random.uniform(1800, 3200))  # outliers
    val = max(180, val)
    acc.append(val)
    return val


def _p95(vals):
    if not vals:
        return 0
    s = sorted(vals)
    k = max(0, int(round(0.95 * (len(s) - 1))))
    return s[k]


def _turn(cid, idx, ts, autor, texto, intent, conf, lat, sent, sent_score, interrup, kb_id, fallback):
    return {
        "turnoId": f"{cid[:8]}-t{idx:03d}",
        "conversationId": cid,
        "indice": idx,
        "ts": ts.isoformat(),
        "autor": autor,
        "texto": texto,
        "intencao": intent,
        "confianca_nlu": conf if conf != "" else "",
        "latencia_resposta_ms": lat if autor == "ia" and lat != "" else "",
        "sentimento": sent,
        "sentimento_score": sent_score,
        "interrupcao": interrup,
        "kb_artigo_id": kb_id,
        "fallback": fallback,
    }


def _evt(cid, ts, tipo, subtipo, lat, cod, msg, sev):
    return {
        "eventId": "evt-" + uuid.uuid4().hex[:12],
        "conversationId": cid,
        "ts": ts.isoformat(),
        "tipo_evento": tipo,
        "subtipo": subtipo,
        "latencia_ms": lat,
        "codigo_erro": cod,
        "mensagem_erro": msg,
        "severidade": sev,
    }


def _doc_json(conv, turns, events, csat):
    doc = dict(conv)
    doc["turns"] = [
        {k: t[k] for k in ("indice", "ts", "autor", "texto", "intencao", "confianca_nlu",
                           "latencia_resposta_ms", "sentimento", "sentimento_score",
                           "interrupcao", "kb_artigo_id", "fallback")}
        for t in sorted(turns, key=lambda x: x["indice"])
    ]
    doc["events"] = [
        {k: e[k] for k in ("ts", "tipo_evento", "subtipo", "latencia_ms", "codigo_erro",
                           "mensagem_erro", "severidade")}
        for e in events
    ]
    doc["csat"] = ({k: csat[0][k] for k in ("nota_csat", "comentario_csat", "ts", "canal_pesquisa")}
                   if csat else None)
    return doc


def _write_csv(path, rows):
    if not rows:
        open(path, "w").close()
        return
    cols = list(rows[0].keys())
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        w.writerows(rows)


def _resumo(conv_rows):
    n = len(conv_rows)
    retidos = sum(c["retido_pela_ia"] for c in conv_rows)
    transf = sum(c["transferido_humano"] for c in conv_rows)
    ura = sum(c["retornou_menu_ura"] for c in conv_rows)
    atendente = sum(c["pediu_atendente"] for c in conv_rows)
    erros = sum(c["teve_erro"] for c in conv_rows)
    lat = [c["latencia_media_ms"] for c in conv_rows]
    tma = [c["tempo_atendimento_seg"] for c in conv_rows]
    notas = [c["nota_csat"] for c in conv_rows if c["nota_csat"] != ""]
    print("\n--- Resumo (sanity check das métricas) ---")
    print(f"  #1 Retencao bruta      : {retidos}/{n} = {100*retidos/n:.1f}%")
    print(f"  #2 TMR medio           : {sum(lat)/n:.0f} ms")
    print(f"  #3 TMA medio           : {sum(tma)/n:.0f} s")
    print(f"  #5 Transbordo humano   : {transf} ({100*transf/n:.1f}%)")
    print(f"  #6 Retorno menu URA    : {ura}")
    print(f"  #7 Pediu atendente     : {atendente}")
    print(f"  #8 Com erro            : {erros}")
    print(f"  #9 CSAT respondido     : {len(notas)} | media {sum(notas)/len(notas):.2f}" if notas else "  #9 CSAT: sem respostas")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Gera dados sintéticos de telemetria do agente de voz.")
    ap.add_argument("--conversas", type=int, default=600)
    ap.add_argument("--dias", type=int, default=30)
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    gerar(args.conversas, args.dias, args.seed)
