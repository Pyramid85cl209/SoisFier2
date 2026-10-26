import asyncio, sys, json
from shots import Shots, C, D

def d(n):  # date relative ISO
    import datetime; return (datetime.date.today() + datetime.timedelta(days=n)).isoformat()

TODAY_DONE = [{"child_id": "C1", "routine_id": "R1", "day": d(0), "stars": 1, "source": "parent", "validated_at": d(0) + "T07:10:00Z", "validated_by": "U", "created_by": "U"},
              {"child_id": "C1", "routine_id": "R2", "day": d(0), "stars": 1, "source": "child", "validated_at": None, "created_by": None},
              {"child_id": "C1", "routine_id": "R4", "day": d(0), "stars": 1, "source": "timer", "validated_at": None, "created_by": None}]

async def main(only=None):
    async with Shots() as s:
        async def scene(name):
            return only is None or name in only

        # ---------- Partie 1 ----------
        if await scene("m1"):
            p = await s.page(session=False)
            await s.act(p, "installEvt = { prompt(){}, userChoice: Promise.resolve() }; render();")
            a = await s.shot(p, "m1", [(".seg.wide button", 1, 1), ("#a-email", 2), ("button[data-act=login]", 3), ("button[data-act=forgot]", 4),
                                       ("button[data-act=goPair]", 5), ("button[data-act=install]", 6), (".lang-btn", 7)], full=True)
            await s.compose("m1", [(a, C("m1", 0))])
        if await scene("m3"):
            p = await s.page(session=False)
            await s.act(p, "S.authMode = 'signup'; render();")
            a = await s.shot(p, "m3a", [(".seg.wide button", 1, 1), ("#a-name", 2), ("#a-email", 3), ("#a-pass", 4), ("button[data-act=signup]", 5)])
            await s.act(p, "$('#a-email').value = 'parent@example.com'; $('#a-pass').value = 'xxxxxx'; await A.signup();")
            b = await s.shot(p, "m3b")
            await s.compose("m3", [(a, C("m3", 0)), (b, C("m3", 1))])
        if await scene("m4"):
            p = await s.page(ovr={"family_members": []})
            await s.act(p, "S.screen = 'onboard'; S.wk = { start: __L.week_start, weekend: __L.weekend, tz: __L.tz }; render();")
            a = await s.shot(p, "m4a", [("#o-name", 1), ("#o-rel", 2), ("button[data-act=editWeek]", 3), ("button[data-act=createFamily]", 4), ("#o-code", 5), ("button[data-act=joinFamily]", 6)], full=True)
            p2 = await s.page(ovr={"children": [], "routines": []})
            b = await s.shot(p2, "m4b")
            await s.compose("m4", [(a, C("m4", 0)), (b, C("m4", 1))])
        if await scene("m5"):
            p = await s.page(session=False)
            await s.act(p, "A.goPair();")
            a = await s.shot(p, "m5", [("#p-code", 1), ("button[data-act=pair]", 2)])
            await s.compose("m5", [(a, C("m5", 0))])
        if await scene("w1"):
            p = await s.page(ovr={"family_members": []})
            await s.act(p, "S.screen = 'onboard'; S.wk = { start: __L.week_start, weekend: __L.weekend, tz: __L.tz }; render(); A.editWeek({ dataset: { mode: 'onboard' } });")
            a = await s.shot(p, "w1", [("#wk-start", 1), (".wk-we", 2, D["weekend"][0] - 1), ("#wk-tz", 3), ("button[data-act=saveWeek]", 4)], sheet=True)
            await s.compose("w1", [(a, C("w1", 0))])
        if await scene("l1"):
            p = await s.page()
            a0 = await s.shot(p, "l1a", [(".lang-btn", 1)])
            await s.act(p, "A.pickLang();")
            a = await s.shot(p, "l1b", [("button[data-act=setLang]", 2, 1)])
            await s.compose("l1", [(a0, C("l1", 0)), (a, C("l1", 1))])

        # ---------- Partie 2a ----------
        if await scene("a1"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } });")
            secs = await p.evaluate("() => [...document.querySelectorAll('.sec h2')].map(h => h.textContent)")
            marks = [(f".sec:nth-of-type({i + 1}) h2", i + 1) for i in range(len(secs))]
            a = await s.shot(p, "a1", marks, full=True)
            await s.compose("a1", [(a, C("a1", 0))])
        if await scene("a2"):
            p = await s.page()
            await s.act(p, "A.newChild(); $('#k-name').value = __L.child;")
            a = await s.shot(p, "a2", [("#k-name", 1), (".emo-row", 2), (".swatches", 3), ("button[data-act=saveChild]", 4)], sheet=True)
            await s.compose("a2", [(a, C("a2", 0))])
        if await scene("a3"):
            p = await s.page(ovr={"routines": []})
            await s.act(p, "A.routineTemplates(); [0,1,2,3,8,9].forEach(i => { const c = $$('.tpl input', dlg)[i]; if (c) c.checked = true; });")
            a = await s.shot(p, "a3a")
            await s.act(p, "dlg.querySelector('.sheet-in').scrollTop = 99999;")
            b = await s.shot(p, "a3b", [("button[data-act=addRoutineTpl]", 1)])
            await s.compose("a3", [(a, C("a3", 0)), (b, C("a3", 1))])

        # ---------- Partie 2b ----------
        if await scene("b0"):
            p = await s.page(ovr={"routines": []})
            await s.act(p, "A.tab({ dataset: { tab: 'routines' } });")
            a = await s.shot(p, "b0", [("button[data-act=routineTemplates]", 1)])
            await s.compose("b0", [(a, C("b0", 0))])
        if await scene("b1"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'routines' } });")
            a = await s.shot(p, "b1a", [(".chip", 1), ("button[data-act=routineTemplates]", 2), ("button[data-act=newRoutine]", 3), (".rt", 4, 1)])
            await s.act(p, "scrollTo(0, 99999);")
            b = await s.shot(p, "b1b", [(".hist li", 5), ("button[data-act=newOneoff]", 6), ("button[data-act=manageOneoffTpl]", 7)])
            await s.compose("b1", [(a, C("b1", 0)), (b, C("b1", 1))])
        if await scene("b2"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'routines' } }); A.routineTemplates();")
            a = await s.shot(p, "b2a", [(".tpl .had", 1)])
            await s.act(p, "const n = $$('.tpl input:not([disabled])', dlg); [0, 3].forEach(i => n[i] && (n[i].checked = true)); dlg.querySelector('.sheet-in').scrollTop = 99999;")
            b = await s.shot(p, "b2b", [("button[data-act=addRoutineTpl]", 2)])
            await s.compose("b2", [(a, C("b2", 0)), (b, C("b2", 1))])
        if await scene("b3"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'routines' } }); A.newRoutine(); $('#f-title').value = __L.routine_new; $('#f-emoji').value = '⚽';")
            a = await s.shot(p, "b3", [("#f-title", 1), (".emo-box", 2), (".seg:has([data-group=moment])", 3), (".days", 4), ("#f-stars", 5), ("#f-place", 6), ("#f-timer", 7), ("#f-bonus", 8), ("button[data-act=saveRoutine]", 9)], sheet=True)
            await s.compose("b3", [(a, C("b3", 0))])
        if await scene("b5"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'routines' } }); A.editRoutine({ dataset: { id: 'R7' } });")
            a = await s.shot(p, "b5", [("button[data-act=delRoutine]", 1), ("button[data-act=saveRoutine]", 2)], sheet=True)
            await s.compose("b5", [(a, C("b5", 0))])
        if await scene("b6"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'routines' } }); A.newOneoff({ dataset: { child: 'C1' } });")
            a = await s.shot(p, "b6a", [("button[data-act=oneoffFrom]", 1, 0)])
            await s.act(p, "A.oneoffFrom({ dataset: { base: '0' } });")
            b = await s.shot(p, "b6b", [("#x-title", 1), (".seg:has([data-group=when])", 2), ("#x-date", 3), (".seg:has([data-group=type])", 4), ("#x-stars", 5), ("#x-keep", 6), ("button[data-act=saveOneoff]", 7)], sheet=True)
            await s.compose("b6", [(a, C("b6", 0)), (b, C("b6", 1))])
        if await scene("b7"):
            p = await s.page()
            a = await s.shot(p, "b7", [(".ring", 1), (".meta", 2)])
            await s.compose("b7", [(a, C("b7", 0))])

        # ---------- Partie 2c ----------
        if await scene("c1"):
            p = await s.page(ovr={"rewards": [], "redemptions": []})
            await s.act(p, "A.tab({ dataset: { tab: 'rewards' } });")
            a = await s.shot(p, "c1a", [(".balance .muted", 1, 0), ("button[data-act=rewardTemplates]", 2), ("button[data-act=newReward]", 3)])
            p2 = await s.page()
            await s.act(p2, "A.tab({ dataset: { tab: 'rewards' } });")
            b = await s.shot(p2, "c1b")
            await s.compose("c1", [(a, C("c1", 0)), (b, C("c1", 1))])
        if await scene("c2"):
            p = await s.page(ovr={"rewards": []})
            await s.act(p, "A.tab({ dataset: { tab: 'rewards' } }); A.rewardTemplates(); [0, 3, 6].forEach(i => { const c = $$('.tpl input', dlg)[i]; if (c) c.checked = true; });")
            a = await s.shot(p, "c2a", [(".tpl input", 1, 0)])
            await s.act(p, "dlg.querySelector('.sheet-in').scrollTop = 99999;")
            b = await s.shot(p, "c2b", [("button[data-act=newEvent]", 2), ("button[data-act=addRewardTpl]", 3)])
            await s.compose("c2", [(a, C("c2", 0)), (b, C("c2", 1))])
        if await scene("c4"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'rewards' } }); A.newEvent(); $('#w-title').value = __L.event; $('#w-fixed').checked = false; $('#w-days').value = 30; $('#w-days').dispatchEvent(new Event('input')); $('#w-date').value = '" + d(12) + "';")
            a = await s.shot(p, "c4", [("#w-title", 1), (".emo-box", 2), ("#w-tier", 3), ("#w-for", 4), ("#w-fixed", 5), ("#w-days", 6), ("#w-preview", 7), ("#w-date", 8), ("button[data-act=saveReward]", 9)], sheet=True)
            await s.compose("c4", [(a, C("c4", 0))])

        # ---------- Malus ----------
        if await scene("d1"):
            p = await s.page(ovr={"penalty_events": []})
            await s.act(p, "A.tab({ dataset: { tab: 'malus' } });")
            a = await s.shot(p, "d1", [(".chip", 1), (".balance", 2), ("button[data-act=breakStar]", 3), ("button[data-act=penaltyCatalog]", 4)])
            await s.compose("d1", [(a, C("d1", 0))])
        if await scene("d2"):
            p = await s.page(ovr={"penalties": []})
            await s.act(p, "A.tab({ dataset: { tab: 'malus' } }); A.penaltyCatalog(); [0, 1].forEach(i => $$('.tpl input', dlg)[i].checked = true); $('#np-title').value = __L.malus_new;")
            a = await s.shot(p, "d2", [(".tpl input", 1, 0), ("#np-title", 2), ("#np-stars", 3), ("button[data-act=breakStar]", 4), ("button[data-act=savePenalties]", 5)], sheet=True)
            await s.compose("d2", [(a, C("d2", 0))])
        if await scene("d3"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'malus' } }); A.breakStar();")
            a = await s.shot(p, "d3", [(".pen", 1, 0), ("#pen-title", 2), ("#pen-stars", 3), ("dialog[open] button[data-act=penaltyCatalog]", 4), ("button.btn.danger[data-act=applyPenalty]", 5)], sheet=True)
            await s.compose("d3", [(a, C("d3", 0))])
        if await scene("d4"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'malus' } });")
            a = await s.shot(p, "d4a", [(".balance", 1), (".vlist li", 2), ("button[data-act=cancelPenalty]", 3)])
            await s.act(p, "A.cancelPenalty({ dataset: { id: 'PE1' } });")
            b = await s.shot(p, "d4b")
            await s.compose("d4", [(a, C("d4", 0)), (b, C("d4", 1))])

        # ---------- Partie 2d ----------
        if await scene("e1"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } });")
            a = await s.shot(p, "e1", [("button[data-act=editChild]", 1), ("button[data-act=deviceCode]", 2), ("button[data-act=childHere]", 3), ("button[data-act=editMember]", 4, 0), ("button[data-act=invite]", 5), ("button[data-act=revokeDevice]", 6)], full=True)
            await s.compose("e1", [(a, C("e1", 0))])
        if await scene("e2"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); A.invite();")
            a = await s.shot(p, "e2a", [("#inv-sel", 1), ("#inv-txt", 2), (".seg:has([data-group=role])", 3), ("button[data-act=makeInvite]", 4)], sheet=True)
            await s.act(p, "navigator.share = () => Promise.resolve(); await A.makeInvite();")
            b = await s.shot(p, "e2b", [("button[data-act=shareInvite]", 5)])
            await s.compose("e2", [(a, C("e2", 0)), (b, C("e2", 1))])
        if await scene("e4"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); A.editMember({ dataset: { id: 'U' } });")
            a = await s.shot(p, "e4a", sheet=True)
            await s.act(p, "A.editMember({ dataset: { id: 'U2' } });")
            b = await s.shot(p, "e4b", [(".seg:has([data-group=role])", 1), ("button[data-act=removeMember]", 2), ("button[data-act=saveMember]", 3)], sheet=True)
            await s.compose("e4", [(a, C("e4", 0)), (b, C("e4", 1))])
        if await scene("e5"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); await A.deviceCode({ dataset: { id: 'C1' } });")
            a = await s.shot(p, "e5a")
            p2 = await s.page(session=False)
            await s.act(p2, "A.goPair(); $('#p-code').value = 'K7P2QX';")
            b = await s.shot(p2, "e5b")
            p3 = await s.page(child=True)
            c = await s.shot(p3, "e5c", [(".lock", 1), (".kid-top .lang-btn", 2)])
            await s.compose("e5", [(a, C("e5", 0)), (b, C("e5", 1)), (c, C("e5", 2))])
        if await scene("e6"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); pinSheet(t('pin.createTitle'), t('pin.createText'));")
            a = await s.shot(p, "e6a")
            p3 = await s.page(child=True)
            b = await s.shot(p3, "e6b", [(".lock", 1)])
            await s.act(p3, "localStorage.setItem('sf:pin', JSON.stringify('1234')); A.exitChild();")
            c = await s.shot(p3, "e6c")
            await s.compose("e6", [(a, C("e6", 0)), (b, C("e6", 1)), (c, C("e6", 2))])
        if await scene("e7"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); A.editChild({ dataset: { id: 'C1' } });")
            a = await s.shot(p, "e7", sheet=True)
            await s.compose("e7", [(a, C("e7", 0))])
        if await scene("e8"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); A.revokeDevice({ dataset: { id: 'DV1' } });")
            a = await s.shot(p, "e8")
            await s.compose("e8", [(a, C("e8", 0))])

        # ---------- Partie 3 ----------
        if await scene("f1"):
            p = await s.page(ovr={"completions": TODAY_DONE[:1]})
            a = await s.shot(p, "f1a", [(".daynav button", 1, 0), (".meta span", 2, 0), (".meta span", 3, 1), (".ring", 4), (".rt .pot", 5, 1)])
            await s.act(p, "scrollTo(0, 99999);")
            b = await s.shot(p, "f1b", [("button[data-act=newOneoff]", 6)])
            await s.compose("f1", [(a, C("f1", 0)), (b, C("f1", 1))])
        if await scene("f2"):
            p = await s.page(ovr={"completions": TODAY_DONE})
            a = await s.shot(p, "f2a", [("button[data-act=validateAll]", 1), (".vbtn.no", 2), (".vbtn.yes", 3)])
            done = [dict(c, validated_at=d(0) + "T08:00:00Z", validated_by="U") for c in TODAY_DONE]
            p2 = await s.page(ovr={"completions": done})
            b = await s.shot(p2, "f2b")
            await s.compose("f2", [(a, C("f2", 0)), (b, C("f2", 1))])
        if await scene("f3"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'rewards' } });")
            a = await s.shot(p, "f3a", [(".gift .btn:not(.ghost)", 1, 0), (".gift .btn.ghost", 2, 0)])
            await s.act(p, "A.pRedeem({ dataset: { id: 'W2' } });")
            b = await s.shot(p, "f3b")
            await s.compose("f3", [(a, C("f3", 0)), (b, C("f3", 1))])
        if await scene("h2"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'rewards' } }); scrollTo(0, 99999);")
            a = await s.shot(p, "h2", [("button[data-act=cancelRedeem]", 1)])
            await s.compose("h2", [(a, C("h2", 0))])

        # ---------- Partie 4 : enfant ----------
        kidc = [{"child_id": "C1", "routine_id": "R1", "day": d(0), "stars": 1, "source": "child", "validated_at": d(0) + "T07:10:00Z", "validated_by": "U"},
                {"child_id": "C1", "routine_id": "R2", "day": d(0), "stars": 1, "source": "child", "validated_at": None}]
        if await scene("g1"):
            p = await s.page(child=True)
            a = await s.shot(p, "g1a", [(".star-count", 1), (".lock", 2), (".hero", 3), (".kcard .k-pot", 4, 1)])
            p2 = await s.page(child=True, ovr={"completions": kidc, "child_stats": [{"child_id": "C1", "family_id": "F", "earned": 140, "done_count": 120, "pending_stars": 1, "pending_count": 1, "spent": 11, "redeemed_count": 1, "broken": 1}]})
            b = await s.shot(p2, "g1b", [(".kcard.pending", 5, 0), (".wait-note", 6)])
            await s.compose("g1", [(a, C("g1", 0)), (b, C("g1", 1))])
        if await scene("g2"):
            p = await s.page(child=True)
            a = await s.shot(p, "g2a", [(".k-timer", 1, 0)])
            await s.act(p, "A.cTimer({ dataset: { id: 'R4' } });", 2200)
            b = await s.shot(p, "g2b", [("#t-done", 2)])
            await s.act(p, "$('#t-done').click();", 300)
            c = await s.shot(p, "g2c", [(".kcard.pending", 3, 0)])
            await s.compose("g2", [(a, C("g2", 0)), (b, C("g2", 1)), (c, C("g2", 2))])
        if await scene("g3"):
            p = await s.page(child=True)
            await s.act(p, "A.ctab({ dataset: { tab: 'gifts' } });")
            a = await s.shot(p, "g3", [(".balance", 1), (".kgift .muted", 2, 0)], full=True)
            await s.compose("g3", [(a, C("g3", 0))])
        if await scene("g6"):
            p = await s.page(child=True)
            await s.act(p, "A.ctab({ dataset: { tab: 'gifts' } });")
            a = await s.shot(p, "g6a", [("button[data-act=cRedeem]", 1, 0)])
            await s.act(p, "A.cRedeem({ dataset: { id: 'W1' } });")
            b = await s.shot(p, "g6b")
            await s.act(p, "closeSheet(); openSheet(`<h2>${t('kid.bravo')} 📖</h2><p>${t('kid.showParents', { title: S.cs.rewards[0].title })}</p><div class=\"sheet-actions\"><button class=\"btn\" data-act=\"closeSheet\">${t('kid.super')}</button></div>`);")
            c = await s.shot(p, "g6c")
            await s.act(p, "closeSheet(); scrollTo(0, 99999);")
            d4 = await s.shot(p, "g6d", [(".hist", 3)])
            await s.compose("g6", [(a, C("g6", 0)), (b, C("g6", 1)), (c, C("g6", 2)), (d4, C("g6", 3))], width=1400)
        if await scene("g4"):
            p = await s.page(child=True)
            await s.act(p, "A.ctab({ dataset: { tab: 'garden' } });")
            a = await s.shot(p, "g4a", [(".scene", 1, 0), (".scene p", 2, 0), (".scene", 3, 1)])
            await s.act(p, "scrollTo(0, 99999);")
            b = await s.shot(p, "g4b", [(".streak", 4), ("#snd", 5), ("button[data-act=pushChild]", 6)])
            await s.compose("g4", [(a, C("g4", 0)), (b, C("g4", 1))])
        if await scene("g5"):
            p = await s.page(child=True)
            await s.act(p, "A.ctab({ dataset: { tab: 'badges' } });")
            a = await s.shot(p, "g5", [(".balance", 1), (".tier-h", 2, 0)])
            await s.compose("g5", [(a, C("g5", 0))])

        # ---------- Partie 5 ----------
        if await scene("i1"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); const sec = $('[data-act=toggleAuto]').closest('.sec'); scrollTo(0, sec.offsetTop - 120);")
            a = await s.shot(p, "i1a", [("[data-act=toggleAuto]", 1)])
            await s.act(p, "S.autoValidate = false; render(); const sec = $('[data-act=toggleAuto]').closest('.sec'); scrollTo(0, sec.offsetTop - 120); toast(t('validate.manualOnly'));")
            b = await s.shot(p, "i1b")
            await s.compose("i1", [(a, C("i1", 0)), (b, C("i1", 1))])
        if await scene("i2"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); const sec = $('#t1').closest('.sec'); scrollTo(0, sec.offsetTop - 120);")
            a = await s.shot(p, "i2a", [("#t1", 1), ("#t2", 2), ("button[data-act=pushParent]", 3)])
            await s.act(p, "localStorage.setItem('sf:pushOn', 'true'); render(); const sec = $('#t1').closest('.sec'); scrollTo(0, sec.offsetTop - 120); toast(t('push.enabled'));")
            b = await s.shot(p, "i2b", [("button[data-act=pushParent]", 4), ("button[data-act=pushOff]", 5)])
            await s.act(p, "toast(t('push.blocked'), true);")
            c = await s.shot(p, "i2c")
            await s.compose("i2", [(a, C("i2", 0)), (b, C("i2", 1)), (c, C("i2", 2))])
        if await scene("i3"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); const sec = $('[data-act=printPlan]').closest('.sec'); scrollTo(0, sec.offsetTop - 160);")
            a = await s.shot(p, "i3a", [("button[data-act=printPlan]", 1)])
            await s.act(p, "printPlanning(['C1']);", 300)
            await p.emulate_media(media="print")
            await p.set_viewport_size({"width": 560, "height": 790})
            b = await s.shot(p, "i3b")
            await p.emulate_media(media="screen"); await p.set_viewport_size({"width": 360, "height": 740})
            await s.compose("i3", [(a, C("i3", 0)), (b, C("i3", 1))])
        if await scene("i4"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); scrollTo(0, 99999);")
            a = await s.shot(p, "i4a", [("button[data-act=setPin]", 1), ("button[data-act=exportData]", 2), ("button[data-act=renameFamily]", 3), ("button[data-act=logout]", 4, 0)])
            await s.act(p, "A.renameFamily();")
            b = await s.shot(p, "i4b")
            await s.compose("i4", [(a, C("i4", 0)), (b, C("i4", 1))])
        if await scene("w2"):
            p = await s.page()
            await s.act(p, "A.tab({ dataset: { tab: 'family' } }); const h = [...$$('.sec h2')].find(x => x.textContent === t('week.title')); scrollTo(0, h.closest('.sec').offsetTop - 120);")
            a = await s.shot(p, "w2a", [("button[data-act=editWeek]", 1)])
            await s.act(p, "A.editWeek({ dataset: { mode: 'family' } });")
            b = await s.shot(p, "w2b", sheet=True)
            await s.compose("w2", [(a, C("w2", 0)), (b, C("w2", 1))])
        # ---------- Partie 6 : Vacances et absences (v27) ----------
        # Liste unique : pause en cours (Maladie), vacances à venir, pause qui chevauche les vacances (la pause l'emporte)
        VAC = {"holiday_periods": [{"id": "H1", "family_id": "F", "child_id": "C1", "name": "", "start_day": d(10), "end_day": d(23), "active": True}],
               "holiday_overrides": [{"period_id": "H1", "routine_id": "R5", "family_id": "F", "child_id": "C1", "status": "off"},
                                     {"period_id": "H1", "routine_id": "R9", "family_id": "F", "child_id": "C1", "status": "required", "days": [1, 2, 3, 4, 5, 6, 7]}],
               "pauses": [{"id": "PZ0", "family_id": "F", "child_id": "C1", "start_day": d(-2), "end_day": d(1), "reason": "sick", "created_at": d(-2) + "T07:00:00Z"},
                          {"id": "PZ1", "family_id": "F", "child_id": "C1", "start_day": d(20), "end_day": d(27), "reason": "trip", "created_at": d(-1) + "T10:00:00Z"}]}
        VAC_JS = ("S.hp.forEach(p => p.name = t('hol.namePlaceholder')); S.holidays.forEach(p => p.name = t('hol.namePlaceholder'));"
                  "S.routines.push({ id: 'R30', family_id: 'F', child_id: 'C1', title: __FXJSON.X.waterGarden, emoji: '🪴', moment: 'soir', stars: 1, days: [1,2,3,4,5,6,7], is_bonus: false, kind: 'regular', active: true, holiday_period_id: 'H1', created_at: '2026-09-01T08:00:00Z', position: 30 });"
                  "S.gardens.C1.days.forEach(x => { if (x.day >= addDays(todayISO(), -2)) { x.paused = true; x.good = false; } });")
        if await scene("v1"):
            p = await s.page(ovr=VAC, h=1010)
            await s.act(p, VAC_JS + "A.tab({ dataset: { tab: 'family' } }); scrollTo(0, $('#vac').offsetTop - 70);")
            a = await s.shot(p, "v1a", [("#vac [data-act=holReview]", 1), ("#vac [data-act=holNew]", 2)])
            await s.act(p, "A.holReview({ dataset: { id: 'H1' } });")
            await p.set_viewport_size({"width": 360, "height": 740})
            b = await s.shot(p, "v1b", [("button[data-act=holDates]", 3), ("button[data-act=holEdit]", 4, 0), ("button[data-act=newRoutine]", 5)], sheet=True)
            await s.compose("v1", [(a, C("v1", 0)), (b, C("v1", 1))])
        if await scene("h1"):
            p = await s.page(ovr=VAC, h=1010)
            await s.act(p, VAC_JS + "A.tab({ dataset: { tab: 'family' } }); scrollTo(0, $('#vac').offsetTop - 70);")
            a = await s.shot(p, "h1a", [("#vac [data-act=editPause]", 1, 0), ("#vac .pz", 2), ("#vac [data-act=newPause]", 3)])
            await p.set_viewport_size({"width": 360, "height": 740}); await s.act(p, "A.newPause();")
            b = await s.shot(p, "h1b", [(".tpl", 4), ("#pz-from", 5), ("#pz-why", 6), ("button[data-act=savePause]", 7)], sheet=True)
            await s.compose("h1", [(a, C("h1", 0)), (b, C("h1", 1))])
        if await scene("h3"):
            p = await s.page(ovr=VAC)
            await s.act(p, VAC_JS + "A.tab({ dataset: { tab: 'family' } }); A.editPause({ dataset: { id: 'PZ0' } });")
            a = await s.shot(p, "h3a", [("#pz-from", 1), ("#pz-to", 2), ("button[data-act=stopPause]", 3)], sheet=True)
            await s.act(p, "A.stopPause({ dataset: { id: 'PZ0' } });")
            b = await s.shot(p, "h3b")
            await s.compose("h3", [(a, C("h3", 0)), (b, C("h3", 1))])
        if await scene("f4"):
            p = await s.page(ovr=VAC)
            await s.act(p, VAC_JS + "render();")
            a = await s.shot(p, "f4", [(".meta .pz", 1), (".ring.pz", 2), (".rlist li", 3, 0)])
            await s.compose("f4", [(a, C("f4", 0))])
        if await scene("g7"):
            p = await s.page(child=True)
            await s.act(p, f"S.cs.garden.pauses = {json.dumps(VAC['pauses'][:1])}; S.cs.garden.days.forEach(x => {{ if (x.day >= addDays(todayISO(), -2)) {{ x.paused = true; x.good = false; }} }}); render();")
            a = await s.shot(p, "g7a", [(".kid-pause p", 1), ("button[data-act=cAnyway]", 2)])
            await s.act(p, "A.cAnyway();")
            b = await s.shot(p, "g7b", [(".kcard", 3, 0)])
            await s.compose("g7", [(a, C("g7", 0)), (b, C("g7", 1))])
        print("erreurs:", s.errs)

asyncio.run(main(set(sys.argv[1:]) or None))
