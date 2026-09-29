import json
import sys
from pathlib import Path

import pytest

pytest.importorskip("PySide6")
pytest.importorskip("pytestqt")
pytest.importorskip("appdirs")

from PySide6 import QtCore

SCRIPT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_ROOT))

from openai_requests_viewer import Viewer


@pytest.fixture()
def log_file(tmp_path: Path) -> Path:
    path = tmp_path / "requests.jsonl"
    entries = [
        {
            "timestamp": "2026-01-19T17:00:00Z",
            "event": "openai.request",
            "request_id": "req-1",
            "method": "POST",
            "url": "https://api.openai.com/v1/responses",
            "body": "{}",
            "user_agent": "space-openai/1.0",
        },
        {
            "timestamp": "2026-01-19T17:00:01Z",
            "event": "openai.response",
            "request_id": "req-1",
            "status": 200,
            "ok": True,
            "body": "{\"id\": \"resp_1\"}",
        },
        {
            "timestamp": "2026-01-19T17:00:02Z",
            "event": "openai.request",
            "request_id": "req-2",
            "method": "POST",
            "url": "https://api.openai.com/v1/responses",
            "body": "{}",
            "user_agent": "space-openai-offline/1.0",
        },
        {
            "timestamp": "2026-01-19T17:00:03Z",
            "event": "openai.response",
            "request_id": "req-2",
            "status": 200,
            "ok": True,
            "body": "{\"id\": \"resp_2\"}",
        },
    ]
    path.write_text("\n".join(json.dumps(entry) for entry in entries) + "\n", encoding="utf-8")
    return path


def test_viewer_loads_grouped_rows(qtbot, log_file: Path) -> None:
    viewer = Viewer(log_path_override=log_file)
    qtbot.addWidget(viewer)
    viewer.load_logs()
    assert viewer.model.rowCount() == 4
    entry_item = viewer.model.item(0, 0)
    assert entry_item is not None
    assert entry_item.text().startswith("[2026-01-19T17:00:00Z] openai.request")
    assert entry_item.rowCount() > 0
    key_item = entry_item.child(0, 0)
    assert key_item.text().startswith("timestamp: ")


def test_selecting_child_updates_details(qtbot, log_file: Path) -> None:
    viewer = Viewer(log_path_override=log_file)
    qtbot.addWidget(viewer)
    viewer.load_logs()
    entry_index = viewer.model.index(1, 0)
    proxy_index = viewer.proxy.mapFromSource(entry_index)
    viewer.tree.selectionModel().select(
        proxy_index,
        QtCore.QItemSelectionModel.ClearAndSelect | QtCore.QItemSelectionModel.Rows,
    )
    viewer.update_details()
    text = viewer.details.toPlainText()
    assert "openai.response" in text
    assert "resp_1" in text


def test_hide_offline_entries(qtbot, log_file: Path) -> None:
    viewer = Viewer(log_path_override=log_file)
    qtbot.addWidget(viewer)
    viewer.hide_offline_checkbox.setChecked(True)
    viewer.load_logs()
    assert viewer.model.rowCount() == 2
