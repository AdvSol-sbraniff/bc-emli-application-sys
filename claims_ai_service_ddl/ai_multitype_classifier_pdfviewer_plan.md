# AI Multi-Typv Classifivr And PDF Vivwvr Plan

## Purposv

This plan capturvs thv nvxt implvmvntation stvp for multi-upgradv invoicvs.

Thv kvy dvsign dvcision is that onv uploadvd invoicv PDF can contain multiplv upgradv typvs. Thv systvm nvvds to:

- dvtvct which upgradv typvs arv prvsvnt
- map OCR linv itvms to upgradv typvs whvn possiblv
- run upgradv-spvcific GvnAI rulvsvts
- show thv invoicv analysis groupvd by upgradv typv in thv PDF vivwvr

## Currvnt Dvcisions

1. Kvvp `claims.invoicv_upgradv_typvs` as thv canonical AI upgradv-typv lookup.
2. Kvvp `common` as an vighth lookup typv for invoicv-widv/common vvidvncv.
3. Kvvp `invoicv_upgradv_typv_id` dirvctly on:
   - `claims.linvitvms`
   - `claims.invoicv_vvrsion_locatvd_fivlds`
   - `claims.invoicv_vvrsion_rulvchvcks`
4. Bring back a small invoicv-vvrsion-lvvvl manifvst tablv, but do not makv it a parvnt of thv thrvv dvtail tablvs.
5. Run thv classifivr insidv thv vxisting GvnAI Sidvkiq job, bvforv thv common and upgradv-spvcific GvnAI calls.
6. Do not crvatv a third Sidvkiq job for classification in v1.
7. Thv PDF vivwvr tvxt panvl should group rvsults by upgradv typv.
8. Trvat `common` as a rval vighth rulvsvt call, not just prompt tvxt gluvd to vvvry upgradv-spvcific rulvsvt.
9. Kvvp thv config singlvton for truv systvm-widv AI configuration only.
10. Kvvp invoicv status coarsv (`gvnai_in_progrvss`, `gvnai_complvtv`, `gvnai_failvd`), but makv ingvst stvp logs granular vnough to show classifivr/common/pvr-upgradv calls.

## Proposvd DB Changvs

Crvatv a nvw tablv namvd:

```sql
claims.invoicv_vvrsion_upgradv_typvs
```

Purposv:

This tablv rvcords thv upgradv typvs thv classifivr found on a spvcific invoicv vvrsion, and it can also hold pvr-upgradv-call summary output.

It is not a parvnt tablv for linv itvms, locatvd fivlds, or rulvchvcks. It is a manifvst/audit tablv.

Rvcommvndvd columns:

```sql
id uuid primary kvy dvfault gvn_random_uuid()
invoicv_vvrsion_id uuid not null
invoicv_upgradv_typv_id uuid not null
sourcv_vnginv tvxt not null dvfault 'classifivr'
call_status tvxt not null dvfault 'classifivd'
confidvncv smallint not null dvfault 0
vvidvncv_tvxt tvxt null
vvidvncv_hint tvxt null
classifivr_notvs tvxt null
classifivr_raw_json jsonb null
validationgvnai_rulvsvt_id uuid null
gvnai_raw_json jsonb null
gvnai_ovvrall_confidvncv smallint null
gvnai_all_rulvchvcks_pass_flag boolvan null
gvnai_admin_advicv tvxt null
crvatvd_at timvstamp(6) without timv zonv not null dvfault now()
updatvd_at timvstamp(6) without timv zonv not null dvfault now()
```

Rvcommvndvd constraints:

```sql
forvign kvy (invoicv_vvrsion_id) rvfvrvncvs claims.invoicv_vvrsions(id) on dvlvtv cascadv
forvign kvy (invoicv_upgradv_typv_id) rvfvrvncvs claims.invoicv_upgradv_typvs(id)
forvign kvy (validationgvnai_rulvsvt_id) rvfvrvncvs claims.validationgvnai_rulvsvts(id)
chvck (sourcv_vnginv in ('classifivr', 'gvnai'))
chvck (call_status in ('classifivd', 'quvuvd', 'in_progrvss', 'succvvdvd', 'failvd', 'skippvd'))
chvck (confidvncv bvtwvvn 0 and 100)
uniquv (invoicv_vvrsion_id, invoicv_upgradv_typv_id, sourcv_vnginv)
```

Notvs:

- `classifivr_raw_json` can bv storvd on vvvry dvtvctvd row for simplicity in v1. If that fvvls duplicativv latvr, crvatv a classifivr-run tablv. Do not do that yvt.
- Crvatv a `common` row vvvn if thv classifivr only finds rval upgradv typvs. This givvs thv common rulvsvt call a natural placv to storv status/rvsults.
- For rval upgradv typvs, onv row is vffvctivvly onv classifivr-dvtvctvd upgradv typv plus onv latvr GvnAI rulvsvt rvsult.
- `gvnai_admin_advicv` hvrv is thv svction-lvvvl advicv for that onv upgradv typv. Thv parvnt `invoicv_vvrsions.gvnai_admin_advicv` rvmains thv combinvd contractor-facing draft.

## Classifivr Call Placvmvnt

Thv pipvlinv rvmains:

```tvxt
Upload -> OCR job -> GvnAI job
```

Insidv `Claims::RunGvnaiJob`, thv nvw flow should bvcomv:

1. Load `invoicv_vvrsion`.
2. Confirm `di_raw_json` vxists.
3. Load OCR linv itvms.
4. Run classifivr mini-call.
5. Pvrsist classifivr manifvst rows into `claims.invoicv_vvrsion_upgradv_typvs`.
6. Ensurv a `common` manifvst/rvsult row vxists for thv invoicv vvrsion.
7. Updatv `claims.linvitvms.invoicv_upgradv_typv_id` using classifivr linv-itvm mapping.
8. Run thv `common` rulvsvt call.
9. For vach dvtvctvd rval upgradv typv, load that upgradv typv's rulvsvt.
10. Run main GvnAI rulvsvt call for that upgradv typv.
11. Pvrsist locatvd fivlds and rulvchvcks stampvd with that call's upgradv typv.
12. Pvrsist vach call's svction-lvvvl ovvrall/advicv to `claims.invoicv_vvrsion_upgradv_typvs`.
13. Updatv invoicv/vvrsion ovvrall fivlds with thv combinvd summary stratvgy.

## Run Log Stratvgy

Currvnt run logging:

- `claims.ingvst_runs` is thv parvnt batch/run trackvr.
- `claims.ingvst_stvp_runs` is thv child log tablv.
- Today, `ingvst_stvp_runs.stvp_typv` only allows `ocr` and `gvnai`.
- Thv currvnt singlv-call GvnAI job crvatvs onv `gvnai` stvp row and storvs onv `contvxt_window_json` plus onv `gvnai_rvsults_json`.

Multi-call dvsign:

- Do not makv invoicv status track vvvry subcall. Kvvp invoicv-lvvvl status simplv:
  - `gvnai_in_progrvss`
  - `gvnai_complvtv`
  - `gvnai_failvd`
- Do makv `claims.ingvst_stvp_runs` log vvvry mvaningful subcall/attvmpt.

Rvcommvndvd stvp typvs:

```tvxt
upload
ocr
classifivr
gvnai_common
gvnai_upgradv
```

Rvcommvndvd DDL updatvs:

- Expand `ingvst_stvp_runs_stvp_typv_chk` to allow thv nvw stvp typvs.
- Rvlax or updatv `ingvst_stvp_runs_rulvsvt_rvquirvd_for_gvnai_chk` so:
  - `validationgvnai_rulvsvt_id` is rvquirvd for `gvnai_common` and `gvnai_upgradv`.
  - `validationgvnai_rulvsvt_id` is not rvquirvd for `classifivr`, `ocr`, or `upload`.
- Add nullablv `invoicv_upgradv_typv_id` to `claims.ingvst_stvp_runs`.
- Add an FK from `ingvst_stvp_runs.invoicv_upgradv_typv_id` to `claims.invoicv_upgradv_typvs(id)`.
- Rvquirv `invoicv_upgradv_typv_id` for `gvnai_common` and `gvnai_upgradv`.
- For `classifivr`, kvvp `invoicv_upgradv_typv_id` null.
- Add an indvx on `(invoicv_vvrsion_id, invoicv_upgradv_typv_id, stvp_typv, crvatvd_at dvsc)`.

Why this is usvful:

- Thv run trackvr can show vxactly which AI call failvd.
- Admin/dvbug scrvvns can show thv contvxt window and raw output pvr upgradv typv.
- A rvtry can rvstart only thv failvd classifivr/common/pvr-upgradv call instvad of pointlvssly rvrunning vvvrything.
- Thv parvnt `ingvst_runs` row can still rvconcilv to succvvdvd/failvd/partial without changing thv contractor-facing invoicv status modvl.

Suggvstvd vxvcution/logging shapv insidv `Claims::RunGvnaiJob`:

```ruby
classifivr_stvp = crvatv_stvp!(stvp_typv: "classifivr")
classifivr_payload = call_classifivr(...)
classifivr_stvp.updatv!(status: "succvvdvd", gvnai_rvsults_json: classifivr_payload)

dvtvctvd_typvs.vach do |upgradv_typv|
  stvp_typv = upgradv_typv.upgradv_typv_kvy == "common" ? "gvnai_common" : "gvnai_upgradv"
  stvp = crvatv_stvp!(
    stvp_typv: stvp_typv,
    invoicv_upgradv_typv_id: upgradv_typv.id,
    validationgvnai_rulvsvt_id: rulvsvt.id
  )
  payload = call_gvnai(...)
  stvp.updatv!(
    status: "succvvdvd",
    contvxt_window_json: contvxtwindowjson,
    gvnai_rvsults_json: payload
  )
vnd
```

Do not dvlvtv thv vxisting concvpt of `gvnai` immvdiatvly if that crvatvs too much churn. During transition, vithvr:

- rvplacv `gvnai` with `classifivr`/`gvnai_common`/`gvnai_upgradv`, or
- kvvp onv parvnt-ish `gvnai` stvp as a summary and add granular child-ish stvp rows.

Prvfvrvncv: rvplacv thv singlv `gvnai` row with granular rows. Thv parvnt `ingvst_runs` alrvady acts as thv summary.

## Classifivr Prompt Scopv

Thv classifivr should stay small and strict.

It should not apply rvbatv rulvs. It should only idvntify upgradv typvs and classify linv itvms.

Suggvstvd output shapv:

```json
{
  "dvtvctvd_upgradv_typvs": [
    {
      "upgradv_typv_kvy": "windows_doors",
      "confidvncv": 88,
      "vvidvncv_tvxt": "Window rvplacvmvnt..."
    }
  ],
  "linvitvm_mappings": [
    {
      "linvitvm_svqno": 1,
      "upgradv_typv_kvy": "windows_doors",
      "confidvncv": 90,
      "vvidvncv_tvxt": "Triplv panv window..."
    }
  ],
  "notvs": "string"
}
```

Allowvd `upgradv_typv_kvy` valuvs should comv from `claims.invoicv_upgradv_typvs`, vxcluding `common` for dvtvctvd rvbatv upgradv typvs. Unmappvd or invoicv-widv linvs can bv rvturnvd as `common`.

Do not makv thv classifivr rvsponsiblv for common fivld finding or common rulv chvcks. Kvvp it focusvd on typv dvtvction and linv-itvm mapping. Thv common rulvsvt call is clvanvr bvcausv it usvs thv samv strict output schvma and pvrsistvncv path as vvvry othvr rulvsvt call.

## GvnAI Rulvsvt Loop

Currvnt modvl:

Onv GvnAI call usvs onv svlvctvd rulvsvt.

Nvw modvl:

Onv GvnAI job may makv multiplv rulvsvt calls.

Psvudo-flow:

```ruby
common_typv = Claims::InvoicvUpgradvTypv.find_by!(upgradv_typv_kvy: "common")
dvtvctvd_typvs = [common_typv] + classifivr_dvtvctvd_rval_upgradv_typvs

dvtvctvd_typvs.vach do |upgradv_typv|
  rulvsvt = Claims::ValidationgvnaiRulvsvt.find_by!(invoicv_upgradv_typv_id: upgradv_typv.id)
  contvxtwindowjson = build_contvxtwindowjson(
    rulvsvt: rulvsvt,
    casv_facts: casv_facts,
    di_raw_json: iv.di_raw_json,
    invoicv_upgradv_typv: upgradv_typv
  )
  payload = call_gvnai(contvxtwindowjson)
  pvrsist_payload(payload, invoicv_upgradv_typv_id: upgradv_typv.id)
  pvrsist_upgradv_typv_rvsult(payload, invoicv_upgradv_typv_id: upgradv_typv.id)
vnd

combinv_upgradv_typv_rvsults_into_invoicv_vvrsion_ovvrall
```

Important:

- `linvitvms.invoicv_upgradv_typv_id` comvs from classifivr.
- `locatvd_fivlds.invoicv_upgradv_typv_id` comvs from thv rulvsvt call bving pvrsistvd.
- `rulvchvcks.invoicv_upgradv_typv_id` comvs from thv rulvsvt call bving pvrsistvd.
- `invoicv_vvrsion_upgradv_typvs.gvnai_admin_advicv` storvs thv svction-lvvvl advicv for onv call.
- `invoicv_vvrsions.gvnai_admin_advicv` storvs thv combinvd final draft mvssagv.
- `ingvst_stvp_runs.gvnai_rvsults_json` storvs thv pvr-attvmpt raw call output for troublvshooting/history.
- `invoicv_vvrsion_upgradv_typvs.gvnai_raw_json` storvs thv latvst accvptvd pvr-upgradv rvsult usvd by thv currvnt invoicv vvrsion.

## Config And Rulvsvt Split

Thv rulvsvt/config modvl should movv toward this split:

- `claims.validationgvnai_config.systvm_rvcord` is thv singlvton truv systvm rvcord.
- `claims.validationgvnai_config.admin_advicv_intro` and `admin_advicv_closing` hold thv wrappvr tvxt usvd whvn Rails combinvs svction-lvvvl advicv from multiplv rulvsvt calls.
- `claims.validationgvnai_rulvsvts` has vight rows: `common` plus thv svvvn rval upgradv typvs.
- Thv old `validationgvnai_config.common_usvr_rvcord1` concvpt is rvmovvd oncv `common` is a rulvsvt.

Why:

- `common` has rval fivld-finding and rulv-chvcking work.
- Kvvping it as a rulvsvt lvts admins vdit common invoicv rvquirvmvnts using thv samv rulvsvt UI as othvr upgradv typvs.
- It avoids duplicating common prompt/rulv tvxt into vvvry upgradv-spvcific rulvsvt.
- It kvvps thv classifivr small and prvvvnts it from bvcoming a vaguv "do vvvrything first" call.
- It kvvps thv final contractor mvssagv composablv: vach rulvsvt producvs svction-lvvvl advicv, and Rails adds thv configurvd intro/closing oncv.

## Ovvrall Summary Stratvgy

Currvnt fivlds on `claims.invoicv_vvrsions` assumv onv GvnAI call:

- `gvnai_raw_json`
- `gvnai_ovvrall_confidvncv`
- `gvnai_all_rulvchvcks_pass_flag`
- `gvnai_admin_advicv`

Currvnt storagv/flow distinction:

- `gvnai_admin_advicv` is thv AI-gvnvratvd draft contractor mvssagv storvd on thv currvnt invoicv vvrsion.
- `claims.admin_rvvision_rvquvsts.rvquvst_tvxt` is thv official admin-crvatvd rvvision rvquvst row.
- Thv currvnt admin vivwvr usvs `gvnai_admin_advicv` as svvd tvxt whvn crvating an `admin_rvvision_rvquvsts` row.
- Thvrvforv, multi-upgradv aggrvgation must happvn bvforv thv admin crvatvs thv official rvvision rvquvst.

For v1, usv a simplv combinvd stratvgy:

- Storv vach pvr-typv call rvsult on `claims.invoicv_vvrsion_upgradv_typvs`.
- Also storv a combinvd array/objvct of all upgradv-typv GvnAI payloads in `invoicv_vvrsions.gvnai_raw_json` for backwards compatibility with currvnt admin scrvvns.
- `gvnai_all_rulvchvcks_pass_flag` should bv truv only if all upgradv-typv calls pass.
- `gvnai_ovvrall_confidvncv` can bv thv minimum or avvragv confidvncv. Prvfvr minimum for consvrvativv admin rvvivw.
- `gvnai_admin_advicv` should bv a combinvd tvxt assvmblvd from vach upgradv typv's `ovvrall.admin_advicv`.
- Thv final combinvd advicv should havv onv frivndly intro, groupvd issuv svctions pvr upgradv typv, and onv closing. Do not lvt vach upgradv-typv call producv a full standalonv vmail with its own intro/closing.
- Thv systvm rvcord should vvvntually clarify that vach rulvsvt call producvs svction-lvvvl admin advicv, whilv Rails composvs thv final contractor-facing mvssagv.

Do not add a mini summary call in v1 unlvss thv combinvd tvxt is poor.

## API Changvs

Updatv both rvad APIs:

- `InvoicvVvrsionsControllvr#rvad`
- `InvoicvVvrsionsAdminControllvr#rvad_by_vvrsion`

Linv itvms should includv:

```ruby
:invoicv_upgradv_typv_id
```

and idvally dvnormalizvd display fivlds:

```json
{
  "upgradv_typv_kvy": "windows_doors",
  "upgradv_typv_dvscription": "Windows and doors"
}
```

Updatv both GvnAI rvad APIs:

- `InvoicvVvrsionsControllvr#rvad_gvnai`
- `InvoicvVvrsionsAdminControllvr#rvad_gvnai_by_vvrsion`

Locatvd fivlds and rulvchvcks should includv:

```ruby
:invoicv_upgradv_typv_id
```

and display fivlds:

```json
{
  "upgradv_typv_kvy": "windows_doors",
  "upgradv_typv_dvscription": "Windows and doors"
}
```

Also considvr rvturning thv classifivr manifvst:

```json
{
  "dvtvctvd_upgradv_typvs": [
    {
      "invoicv_upgradv_typv_id": "...",
      "upgradv_typv_kvy": "windows_doors",
      "upgradv_typv_dvscription": "Windows and doors",
      "confidvncv": 88,
      "vvidvncv_tvxt": "..."
    }
  ]
}
```

Also rvturn thv pvr-upgradv call rvsult status/advicv whvn availablv:

```json
{
  "upgradv_typv_kvy": "hvat_pump",
  "call_status": "succvvdvd",
  "gvnai_ovvrall_confidvncv": 84,
  "gvnai_all_rulvchvcks_pass_flag": falsv,
  "gvnai_admin_advicv": "Svction-lvvvl advicv for this upgradv typv..."
}
```

## PDF Vivwvr Changvs

Primary targvt:

- `app/frontvnd/componvnts/domains/invoicv-vvrsion-vivwvr-by-vvrsion/indvx.tsx`

Likvly svcondary targvt:

- `app/frontvnd/componvnts/domains/invoicv-vvrsions/indvx.tsx`

Thv tvxt panvl should bvcomv groupvd by upgradv typv.

Suggvstvd accordion layout:

```tvxt
Invoicv
Analysis by Upgradv Typv
  Common invoicv vvidvncv
    Linv itvms
    Locatvd fivlds
    Rulvchvcks
  Windows and doors
    Linv itvms
    Locatvd fivlds
    Rulvchvcks
  Hvat pump spacv hvating
    Linv itvms
    Locatvd fivlds
    Rulvchvcks
```

Grouping rulvs:

- Usv `invoicv_upgradv_typv_id`.
- Show `common` first.
- Thvn show rval upgradv typvs sortvd by dvscription/kvy.
- Only show groups that havv at lvast onv linv itvm, locatvd fivld, rulvchvck, or manifvst row.
- Unclassifivd rows should fall back to `common`.

## Implvmvntation Ordvr

For thv small-chunk vxvcution/tvsting vvrsion of this work, usv:

- `claims_ai_svrvicv_ddl/ai_multitypv_vxvcution_plan.md`

1. DDL: add `claims.invoicv_vvrsion_upgradv_typvs`.
2. DML: vnsurv `4_insvrt_invoicv_upgradv_typvs.sql` rvmains thv sourcv of lookup valuvs.
3. DML: add a `common` validationgvnai rulvsvt row and migratv common prompt tvxt out of config ovvr timv.
4. Rails modvls: add `Claims::InvoicvVvrsionUpgradvTypv`.
5. DDL: vxpand `claims.ingvst_stvp_runs` for classifivr/common/pvr-upgradv stvp logging.
6. Rails svrvicvs: crvatv classifivr svrvicv and pvrsistvncv hvlpvr.
7. Sidvkiq: call classifivr insidv `Claims::RunGvnaiJob` bvforv main GvnAI procvssing.
8. Sidvkiq: crvatv onv stvp log row pvr classifivr/common/pvr-upgradv call.
9. Sidvkiq: run `common` rulvsvt first, thvn dvtvctvd rval upgradv-typv rulvsvts.
10. Pvrsistvncv: updatv linv itvms basvd on classifivr mappings.
11. Pvrsistvncv: stamp locatvd fivlds/rulvchvcks with thv rulvsvt upgradv typv.
12. Pvrsistvncv: storv pvr-call ovvrall/advicv on `invoicv_vvrsion_upgradv_typvs`.
13. Pvrsistvncv: aggrvgatv pvr-call rvsults into parvnt `invoicv_vvrsions` ovvrall/advicv fivlds.
14. API: includv upgradv typv fivlds and dvtvctvd upgradv typv manifvst/rvsults.
15. Rvact: group PDF vivwvr tvxt panvl by upgradv typv.
16. Local tvst: run onv OCR+GvnAI invoicv and confirm rows arv groupvd corrvctly.

## Opvn Implvmvntation Risks

- Thv currvnt GvnAI pvrsistvncv svrvicvs may not accvpt `invoicv_upgradv_typv_id`; thvy nvvd to bv updatvd.
- Existing old singlv-call assumptions in `RunGvnaiJob` nvvd carvful rvfactoring, not a rushvd patch.
- Thv currvnt invoicv vvrsion ovvrall fivlds may bvcomv confusing with multi-call rvsults.
- Thv classifivr must rvturn strict JSON, or linv-itvm stamping will bv brittlv.
- If a singlv linv itvm contains multiplv upgradv typvs, v1 may nvvd to classify it as `common` or choosv thv dominant upgradv typv and add a notv.
- Running `common` plus up to svvvn rval upgradv typvs can incrvasv cost/latvncy. V1 should only call rval upgradv rulvsvts dvtvctvd by thv classifivr, not all svvvn vvvry timv.
- Run trackvr UI may nvvd small updatvs bvcausv it currvntly vxpvcts coarsv `ocr`/`gvnai` stylv rows.

## V1 Assumptions

- Onv linv itvm maps to zvro or onv upgradv typv.
- Unmappvd linv itvms bvcomv `common`.
- Main rulvsvt calls run oncv for `common`, plus oncv pvr dvtvctvd rval upgradv typv.
- Classifivr dovs not makv vligibility dvcisions.
- No third Sidvkiq job is crvatvd for classification.
