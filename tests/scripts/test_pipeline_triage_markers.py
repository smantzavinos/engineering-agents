"""Triage markers with attributes (fields=, decided=) are what the triage prompt writes; the dispatcher must read them.

Ported from gm-agent-pipeline (pipeline/test_triage_marker_attrs.py).
Requirement: FR-001
"""
import importlib.util, os, pathlib, unittest
from unittest import mock

SCRIPTS = __import__('pathlib').Path(__file__).resolve().parents[2] / 'scripts'
HERE = pathlib.Path(__file__).resolve().parent


def load():
    env = {"PIPELINE_OWNERS": "owner", "PR_AGENT_HANDLE": "/devbot @owner", "PIPELINE_SHARED_ACCOUNT": "1"}
    with mock.patch.dict(os.environ, env), mock.patch("sys.argv", ["x", "list"]):
        spec = importlib.util.spec_from_file_location("pd_attrs", SCRIPTS / "pipeline-dispatch.py")
        m = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(m)
        except SystemExit:
            pass
    return m


def c(i, body, login="owner", at="2026-10-21T11:00:00Z"):
    return {"id": i, "user": {"login": login}, "body": body, "created_at": at,
            "html_url": f"https://github.com/o/r/issues/495#issuecomment-{i}"}


class TriageMarkerAttributes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.d = load()

    def test_ready_with_fields_ends_an_older_question(self):
        cs = [c(1, "🤖 **Needs your decision**\n\n1. which?\n\n<!-- triage outcome=clarify -->"),
              c(2, "/devbot answer: 1 none"),
              c(3, '🤖 **Ready to schedule**\n\n<!-- triage outcome=ready fields="Size=S Priority=P2" decided="x" -->')]
        self.assertEqual(self.d.wait_kind(cs), (None, None))

    def test_clarify_with_fields_is_a_question(self):
        cs = [c(1, '🤖 **Needs your decision**\n\n1. which?\n\n<!-- triage outcome=clarify fields="Size=S" -->')]
        kind, anchor = self.d.wait_kind(cs)
        self.assertEqual((kind, anchor and anchor["id"]), ("answer", 1))


if __name__ == "__main__":
    unittest.main()
