"""Goi Gemini NHANH cho chat: tat / giam "thinking" de tra loi trong ~1-2 giay.

Khong phu thuoc Gemini that (de test). app.py truyen vao ham raw_call:
    raw_call(contents, config) -> (text | None, config_bi_tu_choi: bool)

Ten tham so thinking khac nhau tuy doi model (2.5 dung thinking_budget,
3.x dung thinking_level) nen thu lan luot; cai nao server tu choi thi bo qua va
nho lai de cac lan sau khong thu lai. Neu tat ca deu bi tu choi -> goi nhu cu.
"""

DEFAULT_MAX_TOKENS = 1024


def thinking_options(model_name):
    name = (model_name or "").lower()

    if "flash-lite" in name:          # lite mac dinh khong thinking
        return []
    if "gemini-3" in name:
        return [{"thinking_level": "minimal"}, {"thinking_level": "low"}]
    if "gemini-2.5" in name and "pro" not in name:
        return [{"thinking_budget": 0}]

    return []


def is_config_error(error):
    """Loi do tham so thinking khong duoc chap nhan (khong phai qua tai / het quota)."""
    return "thinking" in str(error).lower()


def call_fast(raw_call, model_name, contents, config, state,
              max_tokens=DEFAULT_MAX_TOKENS):
    """Tra ve text hoac None. `state` la dict dung chung giua cac lan goi."""
    base = dict(config or {})
    options = thinking_options(model_name)
    bad = state.setdefault("bad", set())
    good = state.get("ok")

    order = ([good] if good is not None else []) + [
        i for i in range(len(options)) if i != good
    ]

    for i in order:
        if i in bad:
            continue

        cfg = {**base, "thinking_config": options[i], "max_output_tokens": max_tokens}
        text, rejected = raw_call(contents, cfg)

        if rejected:
            bad.add(i)
            continue

        if text is not None:
            state["ok"] = i

        return text

    text, _ = raw_call(contents, base)
    return text