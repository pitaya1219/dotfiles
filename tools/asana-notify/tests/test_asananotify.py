#!/usr/bin/env python3
"""asana-notify の判定ロジックの回帰テスト。

    python3 tools/asana-notify/tests/test_asananotify.py

トークンもネットワークも要らない範囲、つまり「何を通知すると決めるか」だけを
固定する。Asana の応答そのものは実機で --dry-run を回して確かめる。

イベントの形は Asana Events API の実際の応答に合わせてある:
resource.resource_type が task / story、コメントは story で type が comment、
システムが書いた履歴(移動した、完了した)は同じ story で type が system。
"""
import json
import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "lib"))
import asananotify  # noqa: E402
from asananotify import (  # noqa: E402
    body_lines, classify_event, due_notes, herdr_argv, load_state,
    new_assignment_notes, summarize,
)

ME = "111"
OTHER = "222"


def check(cond, label):
    print(("ok   " if cond else "FAIL ") + label)
    return bool(cond)


def event(action, rtype, gid="900", user=OTHER, subtype=None, **extra):
    resource = {"gid": gid, "resource_type": rtype}
    if subtype:
        resource["resource_subtype"] = subtype
    return {
        "user": {"gid": user, "resource_type": "user"},
        "action": action,
        "resource": resource,
        **extra,
    }


def task(gid, name="task", due=None):
    t = {"gid": gid, "name": name, "permalink_url": f"https://app.asana.com/0/0/{gid}"}
    if due:
        t["due_on"] = due
    return t


def test_classify():
    ok = True
    ok &= check(
        classify_event(event("added", "story"), ME) == {"kind": "story", "gid": "900"},
        "他人が付けた story は拾う")
    ok &= check(
        classify_event(event("added", "story", user=ME), ME) is None,
        "自分の操作は通知しない")
    ok &= check(
        classify_event(event("added", "task"), ME) == {"kind": "task_added", "gid": "900"},
        "ボードに増えた task は拾う")
    ok &= check(
        classify_event(event("deleted", "task"), ME) is None,
        "削除は通知しない")
    ok &= check(
        classify_event(event("removed", "task"), ME) is None,
        "ボードから外れたものは通知しない")
    ok &= check(
        classify_event(
            event("changed", "task", change={"field": "assignee"}), ME) is None,
        "assignee の変更は My Tasks 側が拾うので二重に鳴らさない")
    ok &= check(
        classify_event(
            event("changed", "task", change={"field": "notes"}), ME) is None,
        "本文の書き換えだけでは鳴らさない")
    ok &= check(
        classify_event({"action": "added", "resource": {"gid": "1", "resource_type": "story"}},
                       ME) == {"kind": "story", "gid": "1"},
        "user が欠けたイベントでも落ちない")

    # resource_subtype がイベントに乗っていれば、システム story を story 本体を
    # 取りに行かずに落とせる。乗っていなければ取得側の判定に委ねる。
    ok &= check(
        classify_event(event("added", "story", subtype="comment_added"), ME)
        == {"kind": "story", "gid": "900"},
        "comment_added の story は拾う")
    for sub in ("assigned", "section_changed", "marked_complete", "due_date_changed"):
        ok &= check(classify_event(event("added", "story", subtype=sub), ME) is None,
                    f"システム story ({sub}) は取得せず落とす")
    ok &= check(
        classify_event(event("added", "story"), ME) == {"kind": "story", "gid": "900"},
        "subtype が無ければ落とさず取得側に委ねる")
    return ok


def test_new_assignments():
    ok = True
    tasks = [task("1"), task("2")]
    ok &= check(new_assignment_notes(None, tasks) == [],
                "初回は基準を取るだけで一斉に鳴らさない")
    ok &= check(len(new_assignment_notes([], tasks)) == 2,
                "基準が空なら両方とも新規")
    notes = new_assignment_notes(["1"], tasks)
    ok &= check(len(notes) == 1 and "2" in notes[0]["body"],
                "既知のタスクは鳴らさず新しいものだけ鳴らす")
    ok &= check(notes[0]["gid"] == "2",
                "note が対象タスクを持つ(2ストリームの合流点で畳むのに使う)")
    ok &= check(new_assignment_notes(["1", "2"], tasks) == [],
                "変化が無ければ何も鳴らさない")
    return ok


def test_due():
    ok = True
    today = "2026-09-08"
    tasks = [task("1", due="2026-09-08"), task("2", due="2026-09-01"),
             task("3", due="2026-12-01"), task("4")]

    silent, baseline = due_notes(tasks, None, today)
    ok &= check(silent == [], "初回は溜まっている期限切れを一斉に鳴らさない")
    ok &= check(sorted(baseline) == ["1", "2"],
                "初回でも基準は記録する(翌日に蒸し返さない)")
    ok &= check(due_notes(tasks, baseline, today)[0] == [],
                "初回の基準を引き継いだ2回目も鳴らない")

    notes, state = due_notes(tasks, {}, today)
    kinds = sorted(n["title"] for n in notes)
    ok &= check(kinds == ["Asana: 期限切れ", "Asana: 本日期限"],
                "本日期限と期限切れをそれぞれの見出しで鳴らす")
    ok &= check(len(notes) == 2, "先の期限と期限なしは鳴らさない")

    again, _ = due_notes(tasks, state, today)
    ok &= check(again == [], "同じ期限で二度は鳴らさない")

    moved = [task("1", due="2026-09-09"), task("2", due="2026-09-01"),
             task("3", due="2026-12-01"), task("4")]
    later, _ = due_notes(moved, state, "2026-09-09")
    ok &= check(len(later) == 1 and "2026-09-09" in later[0]["body"],
                "期限を動かして再び到達したら鳴らす")

    _, pruned = due_notes([task("1", due="2026-09-08")], state, today)
    ok &= check(list(pruned) == ["1"],
                "My Tasks から消えたタスクは記録から落とす")

    # 放置したタスクが「本日期限 → 翌日に期限切れ → 以降は無言」を辿ること。
    # 段階を記録せず期限日だけを鍵にしていたときは、当日の通知が組を使い切って
    # しまい期限切れに到達しなかった。
    roll = [task("5", due="2026-09-08")]
    d1, s1 = due_notes(roll, {}, "2026-09-08")
    d2, s2 = due_notes(roll, s1, "2026-09-09")
    d3, s3 = due_notes(roll, s2, "2026-09-10")
    ok &= check([n["title"] for n in d1] == ["Asana: 本日期限"], "当日は本日期限")
    ok &= check([n["title"] for n in d2] == ["Asana: 期限切れ"],
                "翌日に一度だけ期限切れとして鳴る")
    ok &= check(d3 == [] and s3 == s2, "その次の日からは黙る")

    # 初回に既に期限切れなら、その段階を記録するので翌日蒸し返さない
    _, base = due_notes([task("6", due="2026-09-01")], None, "2026-09-08")
    ok &= check(due_notes([task("6", due="2026-09-01")], base, "2026-09-09")[0] == [],
                "初回に期限切れで基準を取ったものを翌日鳴らし直さない")
    return ok


def test_resolve_value():
    ok = True
    ok &= check(asananotify._resolve_value({"token": "raw"}, "token") == "raw",
                "文字列はそのまま")
    ok &= check(asananotify._resolve_value({}, "token") == "",
                "未設定は空文字")
    ok &= check(
        asananotify._resolve_value({"token": {"command": "echo secret"}}, "token") == "secret",
        "command は実行して stdout を採る")
    ok &= check(
        asananotify._resolve_value({"token": {"command": "exit 1"}}, "token") == "",
        "command が失敗しても例外にせず空文字")
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "tok"
        f.write_text("from-file\n")
        ok &= check(
            asananotify._resolve_value({"token": {"file": str(f)}}, "token") == "from-file",
            "file は読んで前後の空白を落とす")
    ok &= check(
        asananotify._resolve_value({"token": {"file": "/nonexistent/x"}}, "token") == "",
        "file が無くても例外にせず空文字")
    return ok


def test_state_version():
    ok = True
    with tempfile.TemporaryDirectory() as d:
        p = Path(d) / "state.json"
        p.write_text(json.dumps({"version": 999, "my_task_gids": ["1"]}))
        ok &= check(load_state(str(p)) == {},
                    "版が違う state は捨てる(古い形を読んで誤爆させない)")
        p.write_text("{ broken")
        ok &= check(load_state(str(p)) == {}, "壊れた state でも落ちない")
        ok &= check(load_state(str(Path(d) / "absent.json")) == {},
                    "state が無ければ空")

        asananotify.save_state({"my_task_gids": ["1"]}, str(p))
        ok &= check(load_state(str(p)).get("my_task_gids") == ["1"],
                    "書いた state を読み戻せる")
    return ok


def test_delivery_shape():
    ok = True
    argv = herdr_argv({"title": "T", "body": "B", "sound": "done"})
    ok &= check(argv == ["herdr", "notification", "show", "T",
                         "--body", "B", "--sound", "done"],
                "herdr の引数列を固定する")
    ok &= check(herdr_argv({"title": "T", "body": "B"})[-1] == "request",
                "sound 未指定なら request")
    ok &= check(summarize("  a\n b  ") == "a b", "空白を畳む")
    ok &= check(len(summarize("あ" * 300)) == 140, "長文は 140 字に切る")
    ok &= check(summarize(None) == "", "本文が無いコメントでも落ちない")

    ok &= check(body_lines("名前", "", "https://x") == "名前\nhttps://x",
                "本文の途中の空行を落とす(strip では届かない位置)")
    ok &= check(body_lines("名前", None) == "名前", "URL が無ければ名前だけ")
    ok &= check(body_lines() == "", "全部空なら空文字")
    return ok


def main():
    ok = True
    for t in (test_classify, test_new_assignments, test_due, test_resolve_value,
              test_state_version, test_delivery_shape):
        print(f"--- {t.__name__} ---")
        ok &= t()
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
