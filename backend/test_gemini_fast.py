"""Test gemini_fast - khong can mang.   python -m pytest test_gemini_fast.py -q"""
import gemini_fast as gf


def make_raw(rejects=(), result="ok"):
    calls = []

    def raw(contents, config):
        calls.append(config)
        tc = config.get("thinking_config")
        if tc is not None and tuple(tc.items())[0][0] in rejects:
            return None, True
        return result, False

    raw.calls = calls
    return raw


def test_chon_tham_so_theo_model():
    assert gf.thinking_options("gemini-2.5-flash") == [{"thinking_budget": 0}]
    assert gf.thinking_options("gemini-3.6-flash")[0] == {"thinking_level": "minimal"}
    assert gf.thinking_options("gemini-2.5-pro") == []
    assert gf.thinking_options("gemini-2.5-flash-lite") == []
    assert gf.thinking_options("") == []


def test_phan_biet_loi_thinking_voi_loi_khac():
    assert gf.is_config_error(ValueError("Unknown field thinking_level"))
    assert not gf.is_config_error(RuntimeError("503 UNAVAILABLE overloaded"))


def test_thanh_cong_ngay_lan_dau_va_gioi_han_token():
    raw, state = make_raw(), {}
    assert gf.call_fast(raw, "gemini-2.5-flash", ["hi"], {"system_instruction": "x"}, state) == "ok"
    assert len(raw.calls) == 1
    cfg = raw.calls[0]
    assert cfg["thinking_config"] == {"thinking_budget": 0}
    assert cfg["max_output_tokens"] == gf.DEFAULT_MAX_TOKENS
    assert cfg["system_instruction"] == "x"               # giu nguyen cau hinh goc


def test_thu_tiep_khi_bi_tu_choi_va_nho_lai():
    raw, state = make_raw(rejects=("thinking_level",)), {}
    # minimal bi tu choi -> thu low (cung thinking_level) cung bi tu choi -> goi nhu cu
    assert gf.call_fast(raw, "gemini-3.6-flash", ["hi"], {}, state) == "ok"
    assert len(raw.calls) == 3
    assert "thinking_config" not in raw.calls[-1]         # cuoi cung: cau hinh goc

    raw2 = make_raw(rejects=("thinking_level",))
    gf.call_fast(raw2, "gemini-3.6-flash", ["hi"], {}, state)
    assert len(raw2.calls) == 1                           # da nho: khong thu lai


def test_nho_tham_so_dung_de_lan_sau_dung_ngay():
    state = {}

    def raw(contents, config):
        level = (config.get("thinking_config") or {}).get("thinking_level")
        return ("x", False) if level == "low" else (None, level is not None)

    assert gf.call_fast(raw, "gemini-3.6-flash", ["hi"], {}, state) == "x"
    assert state["ok"] == 1

    seen = []

    def raw2(contents, config):
        seen.append(config.get("thinking_config"))
        return "y", False

    gf.call_fast(raw2, "gemini-3.6-flash", ["hi"], {}, state)
    assert seen == [{"thinking_level": "low"}]


def test_qua_tai_khong_bi_nham_voi_loi_cau_hinh():
    def raw(contents, config):
        return None, False                                # het key / qua tai

    state = {}
    assert gf.call_fast(raw, "gemini-2.5-flash", ["hi"], {}, state) is None
    assert "ok" not in state


def test_model_khong_ho_tro_thi_goi_nhu_cu():
    raw = make_raw()
    assert gf.call_fast(raw, "gemini-2.5-pro", ["hi"], {"a": 1}, {}) == "ok"
    assert raw.calls == [{"a": 1}]