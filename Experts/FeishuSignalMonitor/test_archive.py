"""归档时序、版本去重和事务回滚；只用临时数据库。"""
import csv
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from store import connect, ingest, set_state, archive_execution

class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.path=Path(self.tmp.name)/"archive.sqlite"
        self.db=connect(self.path)
        with self.db: set_state(self.db,"live_since",100)
    def tearDown(self):
        self.db.close()
        self.tmp.cleanup()
    def msg(self,content="4180压力",**extra):
        return dict(message_id="m1",sender={"id":"teacher"},create_time=110,
                    msg_type="text",content=content,**extra)
    def rows(self,table):
        return self.db.execute("SELECT * FROM "+table+" ORDER BY id").fetchall()
    def test_message_transition_reversion_and_withdrawal(self):
        a=self.msg()
        with patch("store.time.time",return_value=200):
            for m in [a,a,self.msg("4180支撑"),a,self.msg(deleted=True)]:
                ingest(self.db,"group",[m])
        rows=self.rows("message_versions")
        self.assertEqual(len(rows),4)
        self.assertEqual([json.loads(r["raw"])["content"] for r in rows[:3]],
                         ["4180压力","4180支撑","4180压力"])
        self.assertTrue(json.loads(rows[-1]["raw"])["deleted"])
        self.assertTrue(all(r["received_at"]==200 and r["source_created"]==110 for r in rows))
    def test_upgrade_baseline_has_current_observation_time(self):
        ingest(self.db,"group",[self.msg()])
        with self.db: self.db.execute("DELETE FROM message_versions")
        with patch("store.time.time",return_value=300):
            ingest(self.db,"group",[self.msg("新点位")])
        rows=self.rows("message_versions")
        self.assertEqual([r["baseline"] for r in rows],[1,0])
        self.assertEqual([r["received_at"] for r in rows],[300,300])
    def test_historical_import_is_not_live_receipt(self):
        with patch("store.time.time",return_value=400):
            ingest(self.db,"group",[self.msg()],historical=True)
        row=self.rows("message_versions")[0]
        self.assertEqual(row["historical"],1)
        self.assertEqual(row["received_at"],400)
    def test_failed_batch_rolls_back_message_archive(self):
        with self.assertRaises(KeyError):
            ingest(self.db,"group",[self.msg(),{}])
        self.assertEqual(self.rows("message_versions"),[])
    def test_state_changes_and_rollback(self):
        with self.db:
            for x in [1,1,2,1]: set_state(self.db,"teacher_levels",{"point":x})
            set_state(self.db,"heartbeat",999)
        self.assertEqual(len(self.rows("point_state_versions")),3)
        with self.assertRaises(RuntimeError),self.db:
            set_state(self.db,"point_editor",{"manual":4180})
            raise RuntimeError()
        self.assertEqual(len(self.rows("point_state_versions")),3)
    def snapshot(self,now=200,active=1,rows=None,note="正常"):
        rows=rows if rows is not None else [["POINT","4180","BUY"]]
        out=io.StringIO()
        w=csv.writer(out)
        w.writerow(["TGA","9",now,active,"XAUUSD.c",len(rows),note])
        w.writerows(rows); w.writerow(["END",len(rows)])
        return out.getvalue()
    def save(self,**kw):
        archive_execution(self.db,{"chat_id":"group","teacher_symbol":"XAUUSD",
                          "symbols":{"XAUUSD":"XAUUSD.c"}},kw.get("now",200),self.snapshot(**kw))
    def test_execution_heartbeat_restart_cancellation_and_reversion(self):
        with patch("store.time.time",return_value=500):
            self.save()
            self.save(now=201,note="心跳")
            self.db.close(); self.db=connect(self.path)
            self.save(now=202)
            self.save(now=203,active=0,rows=[])
            self.save(now=204)
        rows=self.rows("execution_versions")
        self.assertEqual(len(rows),3)
        self.assertEqual([r["generated_at"] for r in rows],[200,203,204])
        self.assertTrue(all(r["recorded_at"]==500 for r in rows))
        self.assertEqual(rows[0]["signature"],rows[-1]["signature"])
    def test_invalid_snapshot_does_not_archive(self):
        with self.assertRaises(ValueError):
            archive_execution(self.db,{},200,"TGA,9,200\n")
        self.assertEqual(self.rows("execution_versions"),[])

if __name__=="__main__": unittest.main()
