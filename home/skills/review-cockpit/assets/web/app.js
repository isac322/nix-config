(() => {
  "use strict";

  const THEME_STORAGE_KEY = "review-cockpit-theme-mode";
  const DEFAULT_STATUSES = ["passed", "pending", "unknown", "failed"];

  const state = {
    report: null,
    handoff: null,
    selectedId: null,
    search: "",
    areas: new Set(),
    harnesses: new Set(),
    activities: new Set(["working", "idle"]),
    statuses: new Set(DEFAULT_STATUSES),
    priorities: new Set(["high", "normal", "low"]),
    needsDecisionOnly: false,
    drafts: new Map(),
    activeQuestionByGroup: new Map(),
    themeMode: "system",
  };

  const $ = (id) => document.getElementById(id);
  const STATUS_LABELS = { passed: "통과", pending: "대기", unknown: "미확인", failed: "실패", blocked: "진행 차단", needs_information: "정보 필요", awaiting_decision: "방향 승인 필요", research_complete: "조사 완료 · QA 전", ready: "검토 준비 완료", implemented_pending_qa: "구현 완료 · QA 대기", approved_not_implemented: "승인됨 · 구현 전", merged: "병합됨", closed: "종료됨", completed: "완료됨" };
  const ACTION_LABELS = { approve: "검토 승인 기록", defer: "보류 기록", request_changes: "수정 요청 기록", add_info: "정보 추가 기록" };
  const HANDOFF_ACTION_LABELS = { approve: "승인", request_changes: "수정 요청", add_info: "정보 추가", defer: "보류" };
  const PHASE_LABELS = { research: "조사", qa_blocked: "QA 차단", qa: "QA", review: "독립 리뷰", implementation: "구현", ready: "검토 준비 완료", "pr-ci-passed": "PR · CI 통과", "closed-without-merge": "병합 없이 종료", merged: "병합 완료", "merged-unreleased": "병합 완료 · 미출시" };
  const ROUTE_NAMES = { existing_fix_pr: "기존 수정 PR", defect_issue: "결함 보고", design_decision: "설계 선택 필요", needs_information: "추가 정보 필요", possibly_superseded: "대체·중복 여부 확인", mixed: "복합 항목", other: "기타" };
  const itemLabel = (item) => String(item || "").replace(/^issue:/, "이슈 #").replace(/^pr:/, "PR #");
  const filterState = (status) => ["merged", "closed", "completed"].includes(status) ? "completed" : ["passed", "ready"].includes(status) ? "passed" : status === "failed" ? "failed" : ["blocked", "needs_information", "awaiting_decision", "research_complete", "pending", "implemented_pending_qa", "approved_not_implemented"].includes(status) ? "pending" : "unknown";
  const filterPriority = (priority) => ["high", "normal", "low"].includes(priority) ? priority : "normal";

  function readInitialThemeMode() {
    try {
      const saved = window.localStorage.getItem(THEME_STORAGE_KEY);
      if (saved === "light" || saved === "dark" || saved === "system") return saved;
    } catch (_error) {
      return "system";
    }
    return "system";
  }

  function applyTheme(mode, persist = false) {
    const validMode = mode === "light" || mode === "dark" || mode === "system" ? mode : "system";
    state.themeMode = validMode;
    const prefersDark = window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches;
    const effectiveTheme = validMode === "system" ? (prefersDark ? "dark" : "light") : validMode;
    document.documentElement.dataset.themeMode = validMode;
    document.documentElement.dataset.theme = effectiveTheme;
    document.querySelectorAll(".theme-option").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.themeOption === validMode));
    });
    if (persist) {
      try {
        window.localStorage.setItem(THEME_STORAGE_KEY, validMode);
      } catch (_error) {
        return;
      }
    }
  }

  function isCompletedGroup(group) {
    const phase = String(group.phase || "").toLowerCase();
    const rawState = String(group.status?.state || "").toLowerCase();
    const reported = String(group.status?.reportedState || "").toLowerCase();
    return Boolean(group.completed) || group.mergeResult?.state === "merged" || rawState === "merged" || rawState === "closed" || reported === "closed" || reported === "completed" || phase === "merged" || phase === "merged-unreleased" || phase === "closed-without-merge" || phase === "completed" || phase === "historical-out-of-current-scope";
  }

  function areaLabel(groupOrArea) {
    const area = typeof groupOrArea === "string" ? groupOrArea : groupOrArea?.area;
    if (!area) return "미분류 영역";
    if (typeof groupOrArea === "object" && groupOrArea.areaLabel) return groupOrArea.areaLabel;
    const catalogEntry = state.report?.areaCatalog?.find((entry) => entry.id === area);
    return catalogEntry?.label || area.replace(/[-_]/g, " ");
  }

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined && text !== null) node.textContent = String(text);
    return node;
  }

  function link(label, href) {
    if (!href || !/^https:\/\//i.test(href) && !href.startsWith("/evidence/")) return null;
    const anchor = element("a", "source-link", label);
    anchor.href = href;
    anchor.target = "_blank";
    anchor.rel = "noopener noreferrer";
    return anchor;
  }

  function mainCiState(result) {
    const value = result?.main_ci?.state;
    return ["passed", "pending", "failed"].includes(value) ? value : "unknown";
  }

  function mergeSummary(group) {
    const result = group.mergeResult;
    if (result?.state !== "merged") return "";
    const ciLabel = mainCiState(result) === "pending" ? "검증 대기" : `검증 ${STATUS_LABELS[mainCiState(result)]}`;
    const commit = typeof result.merge_commit === "string" && result.merge_commit ? ` · ${result.merge_commit.slice(0, 12)}` : "";
    return `PR #${result.pr || "미확인"} 병합됨${commit} · main CI ${ciLabel}`;
  }

  function stateOf(group) {
    const phase = String(group.phase || "").toLowerCase();
    const ownerState = group.status?.state;
    const reported = String(group.status?.reportedState || "").toLowerCase();
    if (isCompletedGroup(group)) return phase === "historical-out-of-current-scope" ? "closed" : group.mergeResult?.state === "merged" || ownerState === "merged" || phase.startsWith("merged") ? "merged" : "closed";
    if (group.ready) return "passed";
    const values = [group.qa?.state, group.review?.state];
    if (values.includes("failed")) return "failed";
    if (["blocked", "needs_information", "awaiting_decision", "research_complete", "implemented_pending_qa", "approved_not_implemented"].includes(ownerState)) return ownerState;
    if (values.includes("pending")) return "pending";
    return ownerState || reported || "unknown";
  }

  function stateClass(value) {
    const category = filterState(value);
    return category === "passed" || category === "completed" ? "pass" : category === "failed" ? "fail" : category === "pending" ? "pending" : "unknown";
  }

  function groupMatches(group) {
    if (isCompletedGroup(group) && !state.statuses.has("completed")) return false;
    const query = state.search.trim().toLowerCase();
    if (query) {
      const haystack = [
        group.id,
        group.title,
        group.area,
        group.areaLabel,
        group.what,
        group.why,
        group.agentActivity?.label,
        ...(group.agentActivity?.harnesses || []),
        ...(group.agentActivity?.harnessLabels || []),
        ...(group.items || []).flatMap((item) => [item.id, item.title, item.author]),
      ].join(" ").toLowerCase();
      if (!haystack.includes(query)) return false;
    }
    const isWorking = Boolean(group.agentActivity?.active);
    if (!state.activities.has(isWorking ? "working" : "idle")) return false;
    if (state.harnesses.size) {
      const groupHarnesses = Array.isArray(group.agentActivity?.harnesses) ? group.agentActivity.harnesses : [];
      if (!groupHarnesses.some((harness) => state.harnesses.has(harness))) return false;
    }
    if (state.areas.size && !state.areas.has(group.area)) return false;
    if (!state.priorities.has(filterPriority(group.priority))) return false;
    if (state.needsDecisionOnly && group.needsDecision !== true) return false;
    const status = stateOf(group);
    if (!state.statuses.has(filterState(status))) return false;
    return true;
  }

  function updateHeader() {
    const report = state.report || {};
    const repository = report.repository || "REVIEW COCKPIT";
    $("repo-eyebrow").textContent = `${repository} / PREMERGE REVIEW`;
    $("repo-badge").textContent = repository;
    document.title = `프리머지 결정 보드 · ${repository}`;
    const release = report.latestRelease;
    $("latest-release").hidden = !release?.tag;
    $("latest-release").textContent = release?.tag ? `릴리스 ${release.tag}` : "";
    const branch = report.baseBranch || "main";
    $("base-sha").textContent = report.baseSha ? `${branch} @ ${String(report.baseSha).slice(0, 12)}` : `${branch} @ 커밋 미확인`;
    const generated = report.generatedAt ? new Date(report.generatedAt) : null;
    $("report-age").textContent = generated && !Number.isNaN(generated.valueOf()) ? `갱신 ${generated.toLocaleString("ko-KR")}` : "갱신 시각 미확인";
  }

  function updateSummary() {
    const report = state.report || {};
    const summary = report.summary || {};
    const groups = Array.isArray(report.groups) ? report.groups : [];
    const synthetic = summary.syntheticDecisions ?? groups.filter((group) => group.qaDecision?.synthetic).length;
    const needsDecision = summary.needsDecision ?? groups.filter((group) => group.needsDecision === true).length;
    const working = summary.working ?? groups.filter((group) => group.agentActivity?.active).length;
    $("summary-total").textContent = summary.total ?? groups.length;
    $("summary-working").textContent = working;
    $("summary-ready").textContent = summary.ready ?? "0";
    $("summary-decisions").textContent = summary.decisions ?? "0";
    $("summary-synthetic").textContent = synthetic;
    $("summary-synthetic-decisions").textContent = synthetic;
    $("summary-needs-decision").textContent = needsDecision;
    $("summary-qa-pending").textContent = (summary.qa?.pending || 0) + (summary.qa?.unknown || 0);
    $("summary-review-pending").textContent = (summary.review?.pending || 0) + (summary.review?.unknown || 0);
    updateHeader();
  }

  function renderAreas() {
    const container = $("area-filters");
    container.replaceChildren();
    const catalog = Array.isArray(state.report.areaCatalog) ? state.report.areaCatalog : [];
    const areas = new Map(catalog.filter((entry) => entry?.id).map((entry) => [entry.id, entry.label || entry.id]));
    for (const group of state.report.groups || []) if (group.area && !areas.has(group.area)) areas.set(group.area, areaLabel(group));
    for (const [area, labelText] of [...areas.entries()].sort((left, right) => left[1].localeCompare(right[1]))) {
      const label = element("label");
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.value = area;
      checkbox.checked = state.areas.has(area);
      checkbox.addEventListener("change", () => {
        checkbox.checked ? state.areas.add(area) : state.areas.delete(area);
        renderList();
      });
      label.append(checkbox, element("span", null, labelText));
      container.append(label);
    }
  }

  function renderHarnesses() {
    const fieldset = $("harness-fieldset");
    const container = $("harness-filters");
    container.replaceChildren();
    const catalog = Array.isArray(state.report?.harnessCatalog) ? state.report.harnessCatalog : [];
    const harnesses = new Map(catalog.filter((entry) => entry?.id).map((entry) => [entry.id, entry.label || entry.id]));
    for (const group of state.report?.groups || []) {
      const ids = group.agentActivity?.harnesses || [];
      const labels = group.agentActivity?.harnessLabels || [];
      ids.forEach((id, idx) => {
        if (id && !harnesses.has(id)) harnesses.set(id, labels[idx] || id);
      });
    }
    for (const selected of [...state.harnesses]) {
      if (!harnesses.has(selected)) state.harnesses.delete(selected);
    }
    fieldset.hidden = harnesses.size === 0;
    for (const [harnessId, labelText] of [...harnesses.entries()].sort((left, right) => left[1].localeCompare(right[1]))) {
      const label = element("label");
      const checkbox = document.createElement("input");
      checkbox.type = "checkbox";
      checkbox.value = harnessId;
      checkbox.checked = state.harnesses.has(harnessId);
      checkbox.addEventListener("change", () => {
        checkbox.checked ? state.harnesses.add(harnessId) : state.harnesses.delete(harnessId);
        renderList();
      });
      label.append(checkbox, element("span", null, labelText));
      container.append(label);
    }
  }

  function selectGroup(group, shouldScroll = false) {
    state.selectedId = group.id;
    renderList();
    renderDetail(group);
    const detailPanel = $("detail-panel");
    if (detailPanel) detailPanel.scrollTop = 0;
    const row = [...$("group-list").querySelectorAll(".group-row")].find((item) => item.dataset.groupId === group.id);
    if (row) {
      row.focus({ preventScroll: true });
      if (shouldScroll) row.scrollIntoView({ behavior: "smooth", block: "nearest" });
    }
  }

  function renderList() {
    const list = $("group-list");
    list.replaceChildren();
    const groups = (state.report?.groups || []).filter(groupMatches);
    if (!groups.some((group) => group.id === state.selectedId)) {
      state.selectedId = groups[0]?.id || null;
      if (groups.length) renderDetail(groups[0]);
      else {
        const empty = element("div", "empty-detail");
        empty.append(element("h2", null, "현재 필터에 맞는 작업이 없습니다."), element("p", null, "검색어를 바꾸거나 필터 초기화를 눌러 주세요."));
        $("detail-panel").replaceChildren(empty);
      }
    }
    const completedCount = (state.report?.groups || []).filter(isCompletedGroup).length;
    const hiddenCompletedSuffix = !state.statuses.has("completed") && completedCount > 0 ? ` · 완료 ${completedCount}개 숨김` : "";
    $("visible-count").textContent = String(groups.length);
    $("list-status").textContent = groups.length ? `${groups.length}개 작업 표시${hiddenCompletedSuffix}` : `표시할 작업 없음${hiddenCompletedSuffix}`;
    for (const group of groups) {
      const status = stateOf(group);
      const row = element("button", "group-row");
      row.type = "button";
      row.dataset.groupId = group.id;
      row.setAttribute("aria-current", state.selectedId === group.id ? "true" : "false");
      const badgeLabel = group.needsDecision === true ? "결정 필요" : STATUS_LABELS[status] || "미확인";
      const badgeTone = group.needsDecision === true ? "pending" : stateClass(status);
      row.setAttribute("aria-label", `${group.title}, 상태 ${badgeLabel}`);
      const top = element("div", "group-row-top");
      top.append(element("h3", null, group.title), element("span", `row-badge ${badgeTone}`, badgeLabel));
      const meta = element("div", "row-meta");
      if (group.agentActivity?.active) {
        meta.append(element("span", "harness-chip", group.agentActivity.label || "작업 중"));
      }
      const itemIds = (group.items || []).map((item) => itemLabel(item.id)).join(", ");
      if (itemIds) meta.append(element("span", null, itemIds));
      meta.append(element("span", null, areaLabel(group)));
      row.append(top, meta);
      row.addEventListener("click", () => selectGroup(group));
      list.append(row);
    }
  }

  function renderGateStrip(group) {
    const strip = element("div", "gate-strip");
    const phaseText = PHASE_LABELS[group.phase] || STATUS_LABELS[group.phase] || "진행 중";
    const qaState = group.qa?.state || "unknown";
    const reviewState = group.review?.state || "unknown";
    const decisionText = group.decision ? (ACTION_LABELS[group.decision.action] || group.decision.action) : group.needsDecision ? "오너 결정 대기" : "대기";
    const entries = [
      ["하네스", group.agentActivity?.active ? (group.agentActivity.label || "작업 중") : "유휴"],
      ["단계", phaseText],
      ["QA", STATUS_LABELS[qaState] || "미확인"],
      ["독립 리뷰", STATUS_LABELS[reviewState] || "미확인"],
      ["결정", decisionText],
    ];
    if (group.currentHead) entries.push(["커밋", String(group.currentHead).slice(0, 12)]);
    for (const [label, value] of entries) {
      const item = element("span", "gate-item");
      item.append(element("span", null, `${label}:`), element("strong", null, value));
      strip.append(item);
    }
    return strip;
  }

  function renderFact(title, content) {
    const block = element("div", "fact-block");
    block.append(element("h3", null, title), element("p", null, content || "자료가 없습니다."));
    return block;
  }

  function normalizeTextKey(value) {
    return String(value || "").replace(/\s+/g, " ").trim().toLowerCase();
  }

  function isMeaningfulValue(value) {
    if (Array.isArray(value)) return value.some((item) => isMeaningfulValue(item));
    const clean = String(value || "").trim();
    if (!clean) return false;
    return !/^(없음|없습니다\.?|자료가 없습니다\.?|미확인|해당 없음|none|n\/a|-)$/i.test(clean);
  }

  function renderWorkBrief(group) {
    const container = element("section", "work-brief");
    const seen = new Set();
    const registerText = (text) => {
      const key = normalizeTextKey(text);
      if (!key || seen.has(key)) return false;
      seen.add(key);
      return true;
    };
    registerText(group.title);

    const leadText = [group.why, group.importance, group.what].find((candidate) => isMeaningfulValue(candidate) && registerText(candidate));
    if (leadText) {
      container.append(element("p", "work-lead", String(leadText).trim()));
    }

    const sections = element("div", "work-sections");
    const appendCard = (title, values, isAlert = false) => {
      const rawItems = (Array.isArray(values) ? values : [values]).flatMap((entry) => (Array.isArray(entry) ? entry : [entry]));
      const distinct = [];
      for (const item of rawItems) {
        if (!isMeaningfulValue(item)) continue;
        const text = String(item).trim();
        if (registerText(text)) distinct.push(text);
      }
      if (!distinct.length) return;
      const card = element("article", isAlert ? "work-card work-card-alert" : "work-card");
      card.append(element("h3", null, title));
      if (distinct.length === 1 && !Array.isArray(values)) {
        card.append(element("p", null, distinct[0]));
      } else if (distinct.length === 1 && distinct[0].length > 90) {
        card.append(element("p", null, distinct[0]));
      } else {
        const list = element("ul");
        for (const line of distinct) list.append(element("li", null, line));
        card.append(list);
      }
      sections.append(card);
    };

    appendCard("현재 문제 및 배경", [group.problem, group.importance, group.what]);
    appendCard("제안된 해결 방향 및 변경", group.proposedChanges);
    appendCard("차단 요인 및 리스크", [group.blockers, group.risks], isMeaningfulValue(group.blockers));
    appendCard("권장 다음 행동", group.nextAction);

    if (sections.childNodes.length) container.append(sections);
    return container;
  }

  function renderEvidenceCard(title, result) {
    const card = element("article", "evidence-card");
    const status = result?.state || "unknown";
    card.append(element("h4", null, title), element("span", `status-chip ${stateClass(status)}`, STATUS_LABELS[status] || "미확인"), element("p", null, result?.summary || "결과 요약이 제공되지 않았습니다."));
    if (result?.source) card.append(element("p", null, `출처: ${result.source}`));
    if (Array.isArray(result?.links) && result.links.length) {
      const links = element("div", "artifact-links");
      for (const item of result.links) {
        const anchor = link(item.label || "증거 열기", item.href);
        if (anchor) links.append(anchor);
      }
      card.append(links);
    }
    if (result?.details) {
      const details = document.createElement("details");
      details.append(element("summary", null, "세부 결과 보기"), element("pre", null, JSON.stringify(result.details, null, 2)));
      card.append(details);
    }
    return card;
  }

  function renderMergeResult(group) {
    const result = group.mergeResult;
    if (!result || typeof result !== "object") return null;
    const section = element("section", "detail-section");
    section.append(element("h3", null, "관측된 실행 결과"), element("p", "decision-help", result.state === "merged" ? mergeSummary(group) : "병합 상태 미확인"));
    const grid = element("div", "detail-grid");
    const pullRequest = element("div", "fact-block");
    pullRequest.append(element("h3", null, "실행 대상 PR"));
    const prLink = link(`PR #${result.pr || "미확인"}`, result.url);
    pullRequest.append(prLink || element("p", null, "PR 링크 미확인"));
    const ciState = mainCiState(result);
    grid.append(
      pullRequest,
      renderFact("검토된 head · 병합 커밋", `${result.reviewed_head || "미확인"} → ${result.merge_commit || "미확인"} (${result.method || "방식 미확인"})`),
      renderFact("병합 후 main CI", ciState === "pending" ? "검증 대기" : `검증 ${STATUS_LABELS[ciState]}`)
    );
    section.append(grid);
    return section;
  }

  function renderPrBriefing(group) {
    const briefing = group.prBriefing;
    if (!briefing?.hasPullRequest) return null;
    const section = element("section", "detail-section");
    section.append(element("h3", null, "PR 출처와 교체 상태"));
    const grid = element("div", "detail-grid");
    const original = element("div", "fact-block");
    original.append(element("h3", null, "원본 PR"));
    const originalLink = link(briefing.originalUrl || "원본 URL 없음", briefing.originalUrl);
    original.append(originalLink || element("p", null, "원본 URL이 제공되지 않았습니다."), element("p", null, `작성자: ${briefing.originalAuthor || "미확인"}`));
    const replacement = element("div", "fact-block");
    replacement.append(element("h3", null, briefing.replacementUrl ? "교체 PR" : "관련 전달 PR"));
    const replacementLink = link(briefing.replacementUrl, briefing.replacementUrl);
    replacement.append(replacementLink || element("p", null, "별도 교체 PR 없음"), element("p", null, `귀속 방식: ${briefing.attributionMethod || "미확인"}`));
    grid.append(original, replacement);
    section.append(grid);
    if (briefing.originalComment?.url || briefing.originalComment?.status) {
      const commentLine = element("p", "decision-help", `원본 PR 안내 댓글: ${briefing.originalComment?.status || "확인됨"}`);
      if (briefing.originalComment?.url) {
        const commentLink = link("댓글 열기", briefing.originalComment.url);
        if (commentLink) commentLine.append(" · ", commentLink);
      }
      section.append(commentLine);
    }
    return section;
  }

  function renderItems(group) {
    const section = element("section", "detail-section");
    section.append(element("h3", null, "포함된 이슈·PR 및 분류"));
    const table = element("table", "method-table");
    const head = element("tr");
    ["대상", "제목", "작성자", "고정 분류"].forEach((title) => head.append(element("th", null, title)));
    const thead = element("thead");
    thead.append(head);
    table.append(thead);
    const body = element("tbody");
    for (const item of group.items || []) {
      const row = element("tr");
      row.append(element("td", null, itemLabel(item.id)), element("td", null, item.title), element("td", null, item.author || "미확인"), element("td", null, ROUTE_NAMES[item.classification?.route?.choice || item.classification?.route] || "미확인"));
      body.append(row);
    }
    table.append(body);
    section.append(table);
    return section;
  }

  function renderDecision(group) {
    const section = element("section", "decision-block");
    const draft = state.drafts.get(group.id);
    const savedAnswers = group.decision?.answers && typeof group.decision.answers === "object" ? group.decision.answers : {};
    const isReplacement = Boolean(group.prBriefing?.replacementUrl);
    const header = element("div", "decision-header");
    header.append(element("h3", null, isReplacement ? "오너 결정 · 교체 PR 검토" : "오너 결정 기록"));
    if (group.decision) {
      header.append(element("span", "status-chip pass", `${ACTION_LABELS[group.decision.action] || group.decision.action} · ${group.decision.savedAt || "시각 미확인"}`));
    } else if (group.needsDecision) {
      header.append(element("span", "status-chip pending", "결정 필요"));
    }
    section.append(header);
    const choiceInputs = [];
    for (const question of group.questions || []) {
      const fieldset = document.createElement("fieldset");
      fieldset.className = "decision-question";
      fieldset.append(element("legend", null, question.question));
      if (question.rationale) fieldset.append(element("p", "decision-help", "권장 근거: " + question.rationale));
      const savedAnswer = savedAnswers[question.id];
      const savedOptionId = savedAnswer && typeof savedAnswer === "object" ? savedAnswer.optionId : null;
      for (const option of question.options || []) {
        const label = element("label");
        const radio = document.createElement("input");
        radio.type = "radio";
        radio.name = "decision-" + question.id;
        radio.dataset.decisionId = question.id;
        radio.dataset.optionId = option.id;
        const isRecommended = option.label === question.recommended || option.id === question.recommended;
        const draftChoice = draft?.choices?.[question.id];
        radio.checked = draftChoice ? draftChoice === option.id : savedOptionId ? savedOptionId === option.id : isRecommended;
        radio.addEventListener("change", () => {
          state.activeQuestionByGroup.set(group.id, question.id);
          rememberDraft();
        });
        choiceInputs.push(radio);
        const copy = element("span");
        copy.append(element("strong", null, isRecommended ? `${option.label} (권장)` : option.label));
        const tradeoffs = [...(Array.isArray(option.tradeoffs) ? option.tradeoffs : []), ...(Array.isArray(option.cons) ? option.cons : [])];
        if (tradeoffs.length) copy.append(element("small", null, "트레이드오프: " + tradeoffs.join(" · ")));
        label.append(radio, copy);
        fieldset.append(label);
      }
      const questionSave = element("button", "question-save-btn", "이 질문 선택 승인 저장");
      questionSave.type = "button";
      questionSave.addEventListener("click", () => {
        const checked = choiceInputs.find((input) => input.checked && input.dataset.decisionId === question.id);
        saveDecision(group, "approve", textarea.value, { decisionId: checked?.dataset.decisionId, optionId: checked?.dataset.optionId });
      });
      fieldset.append(questionSave);
      const savedLabel = (question.options || []).find((option) => option.id === savedOptionId)?.label;
      if (savedLabel) fieldset.append(element("p", "decision-help", "저장된 선택: " + savedLabel + " · " + (savedAnswer.savedAt || "시각 미확인")));
      section.append(fieldset);
    }
    const textarea = document.createElement("textarea");
    textarea.className = "decision-note";
    textarea.maxLength = 2000;
    textarea.placeholder = "결정 근거, 보류 이유, 추가로 남길 피드백이나 메모를 적으세요. (선택)";
    textarea.value = draft ? draft.note : group.decision?.note || "";
    function rememberDraft() {
      const choices = {};
      for (const input of choiceInputs) if (input.checked) choices[input.dataset.decisionId] = input.dataset.optionId;
      state.drafts.set(group.id, { note: textarea.value, choices });
    }
    textarea.addEventListener("input", rememberDraft);
    section.append(textarea);
    const actions = element("div", "decision-actions");
    const entries = [["approve", isReplacement ? "교체 PR 검토 승인" : "검토 승인", true], ["defer", "보류", false], ["request_changes", "수정 요청", false], ["add_info", "정보 추가", false]];
    for (const [action, label, primary] of entries) {
      const button = element("button", primary ? "primary" : "", label);
      button.type = "button";
      button.addEventListener("click", () => {
        const targetId = action === "defer" ? null : state.activeQuestionByGroup.get(group.id) || choiceInputs.find((input) => input.checked)?.dataset.decisionId;
        const checked = targetId ? choiceInputs.find((input) => input.checked && input.dataset.decisionId === targetId) : null;
        saveDecision(group, action, textarea.value, { decisionId: checked?.dataset.decisionId, optionId: checked?.dataset.optionId });
      });
      actions.append(button);
    }
    section.append(actions);
    return section;
  }

  function renderTechnicalDetails(group) {
    const technical = document.createElement("details");
    technical.className = "technical-details";
    technical.append(element("summary", null, "포함된 이슈·PR 표, 계획된 QA 및 원자료 출처 보기"), renderItems(group));
    if (isMeaningfulValue(group.qaPlan)) {
      const qaPlanCard = element("article", "evidence-card");
      qaPlanCard.append(element("h4", null, "계획된 QA 시나리오"));
      if (Array.isArray(group.qaPlan)) {
        const list = element("ul");
        for (const item of group.qaPlan) list.append(element("li", null, item));
        qaPlanCard.append(list);
      } else {
        qaPlanCard.append(element("p", null, String(group.qaPlan)));
      }
      technical.append(qaPlanCard);
    }
    if ((group.sourceRefs || []).length) {
      const refCard = element("article", "evidence-card");
      refCard.append(element("h4", null, "원자료 및 참조 경로"));
      const sourceList = element("ul");
      for (const ref of group.sourceRefs || []) sourceList.append(element("li", null, ref));
      refCard.append(sourceList);
      technical.append(refCard);
    }
    return technical;
  }

  function renderSyntheticDecision(group) {
    if (!group.qaDecision?.synthetic) return null;
    const section = element("section", "detail-section");
    const card = element("div", "fact-block");
    card.append(element("h3", null, "QA 저장 시험 기록 (오너 결정 집계 제외)"), element("p", null, group.qaDecision.label));
    section.append(card);
    return section;
  }

  function renderDetail(group) {
    const panel = $("detail-panel");
    panel.replaceChildren();
    const inner = element("div", "detail-inner");
    const header = element("div", "detail-header");
    const metaTop = element("div", "detail-meta-top");
    const pills = element("div", "detail-item-pills");
    if (group.agentActivity?.active) {
      pills.append(element("span", "item-pill harness-pill", group.agentActivity.label || "작업 중"));
    }
    pills.append(element("span", "item-pill", areaLabel(group)));
    for (const item of group.items || []) {
      const labelText = itemLabel(item.id);
      if (item.url && /^https:\/\//i.test(item.url)) {
        const anchor = element("a", "item-pill source-link", `${labelText} ↗`);
        anchor.href = item.url;
        anchor.target = "_blank";
        anchor.rel = "noopener noreferrer";
        pills.append(anchor);
      } else {
        pills.append(element("span", "item-pill", labelText));
      }
    }
    metaTop.append(pills);
    const status = stateOf(group);
    const titleRow = element("div", "detail-title-row");
    titleRow.append(
      element("h2", null, group.title),
      element("span", `detail-state ${stateClass(status)}`, status === "merged" ? "병합됨" : status === "closed" ? "종료됨" : group.ready ? "통과 가능" : STATUS_LABELS[status] || "미확인")
    );
    header.append(metaTop, titleRow, renderGateStrip(group));
    inner.append(header);

    inner.append(renderWorkBrief(group));
    inner.append(renderDecision(group));

    const evidence = element("section", "detail-section");
    evidence.append(element("h3", null, "QA 및 독립 리뷰 증거"));
    const statusSummary = String(group.status?.summary || "").trim();
    if (statusSummary && statusSummary !== String(group.qa?.summary || "").trim() && statusSummary !== String(group.review?.summary || "").trim()) {
      evidence.append(element("p", "decision-help", `진행 요약: ${statusSummary}`));
    }
    const evidenceGrid = element("div", "evidence-grid");
    evidenceGrid.append(renderEvidenceCard("QA 검증", group.qa), renderEvidenceCard("독립 리뷰", group.review));
    evidence.append(evidenceGrid);
    if (group.links?.length) {
      const links = element("div", "artifact-links");
      for (const item of group.links) {
        const anchor = link(item.label || "증거 열기", item.href);
        if (anchor) links.append(anchor);
      }
      evidence.append(links);
    }
    inner.append(evidence);

    const mergeResult = renderMergeResult(group);
    if (mergeResult) inner.append(mergeResult);
    const pr = renderPrBriefing(group);
    if (pr) inner.append(pr);
    const syntheticDecision = renderSyntheticDecision(group);
    if (syntheticDecision) inner.append(syntheticDecision);
    inner.append(renderTechnicalDetails(group));
    panel.append(inner);
  }

  function closeDrawers() {
    $("audit-panel").hidden = true;
    $("handoff-panel").hidden = true;
    $("audit-toggle").setAttribute("aria-expanded", "false");
    $("handoff-toggle").setAttribute("aria-expanded", "false");
  }

  function renderAudit() {
    const panel = $("audit-panel");
    panel.replaceChildren();
    const audit = state.report.methodAudit || {};
    const header = element("div", "drawer-header");
    header.append(element("h2", null, "분류 방법 감사"));
    const closeBtn = element("button", "text-button", "닫기 ✕");
    closeBtn.type = "button";
    closeBtn.addEventListener("click", closeDrawers);
    header.append(closeBtn);
    panel.append(header, element("p", null, "이 실행에서 고정된 분류 메타데이터입니다. 분류 라벨은 실행 증거가 아니며 QA·독립 리뷰와 분리해 평가합니다."));
    const boxes = element("div", "audit-list");
    for (const [title, value] of [["분류 원천", audit.classificationSource || "미확인"], ["기준 커밋", audit.baseSha || "미확인"], ["제외 작성자", (audit.excludedAuthors || []).join(", ") || "없음"]]) {
      const box = element("div", "audit-box");
      box.append(element("strong", null, title), element("span", null, value));
      boxes.append(box);
    }
    const excluded = element("div", "fact-block audit-excluded");
    excluded.append(element("h3", null, "제외 항목 수"), element("p", null, JSON.stringify(audit.excludedCounts || {}, null, 2)));
    panel.append(boxes, excluded, element("p", null, audit.excludedNote || ""));
  }

  function renderHandoff() {
    const panel = $("handoff-panel");
    const handoff = state.handoff;
    panel.replaceChildren();
    const drawerHeader = element("div", "drawer-header");
    drawerHeader.append(element("h2", null, "수집된 피드백 요약"));
    const closeBtn = element("button", "text-button", "닫기 ✕");
    closeBtn.type = "button";
    closeBtn.addEventListener("click", closeDrawers);
    drawerHeader.append(closeBtn);
    panel.append(drawerHeader);
    if (!handoff) {
      panel.append(element("p", "handoff-summary", "피드백 요약을 불러오지 못했습니다."));
      $("handoff-toggle").textContent = "수집된 피드백";
      return;
    }
    const queue = Array.isArray(handoff.queue) ? handoff.queue : [];
    const counts = handoff.counts || {};
    const submitted = Boolean(handoff.submission?.submitted);
    const submitBtn = $("submit-feedback");
    if (submitBtn) {
      submitBtn.textContent = submitted ? "제출 완료 ✓ (재제출)" : "피드백 제출 (에이전트 전달)";
      submitBtn.classList.toggle("submitted", submitted);
    }
    const statusSuffix = submitted && handoff.submission?.submittedAt ? ` · 제출 완료 (${handoff.submission.submittedAt})` : " · 미제출";
    const summary = element("p", "handoff-summary", `기록된 피드백: 승인 ${counts.approvedCount || 0} · 수정 요청 ${counts.changesRequestedCount || 0} · 정보 추가 ${counts.infoRequestedCount || 0} · 보류 ${counts.deferredCount || 0} · 남은 결정 필요 ${counts.undecidedCount || 0}${statusSuffix}`);
    panel.append(summary);
    const actions = element("div", "handoff-actions");
    const drawerSubmit = element("button", "submit-button", submitted ? "제출 완료 ✓ (재제출)" : "피드백 제출 (에이전트 전달)");
    drawerSubmit.id = "handoff-submit";
    drawerSubmit.type = "button";
    drawerSubmit.addEventListener("click", submitFeedback);
    actions.append(drawerSubmit);
    const copyButtons = [["handoff-copy-prompt", "피드백 요약 복사", handoff.resumePrompt || ""], ["handoff-copy-json", "JSON 복사", JSON.stringify(handoff, null, 2)], ["handoff-copy-cli", "CLI 명령 복사", 'python3 "${REVIEW_COCKPIT_SKILL_DIR:-$HOME/.agents/skills/review-cockpit}/scripts/cockpit.py" handoff --root "${REVIEW_COCKPIT_ROOT:?set REVIEW_COCKPIT_ROOT}" --format prompt']];
    for (const [id, label, value] of copyButtons) {
      const button = element("button", "", label);
      button.id = id;
      button.type = "button";
      button.addEventListener("click", async () => {
        try {
          await copyText(value);
          showToast(id === "handoff-copy-prompt" ? "피드백 요약을 복사했습니다." : "클립보드에 복사했습니다.");
        } catch (_error) {
          showToast("클립보드에 복사하지 못했습니다.");
        }
      });
      actions.append(button);
    }
    panel.append(actions);
    const list = element("ul", "handoff-list");
    for (const item of queue) {
      const entry = element("li", "handoff-item");
      const header = element("div", "handoff-item-header");
      header.append(element("h3", null, item.title || item.groupId));
      const jump = element("button", "handoff-jump", "상세 열기");
      jump.type = "button";
      jump.addEventListener("click", () => {
        const group = state.report?.groups.find((candidate) => candidate.id === item.groupId);
        if (group) {
          closeDrawers();
          selectGroup(group, true);
        }
      });
      header.append(jump);
      entry.append(header);
      const badges = element("div", "handoff-badges");
      for (const value of item.items || []) badges.append(element("span", "handoff-badge", itemLabel(value)));
      if (item.actionLabel || item.action) badges.append(element("span", "handoff-badge", item.actionLabel || HANDOFF_ACTION_LABELS[item.action] || item.action));
      for (const answer of item.answers || []) if (answer.optionLabel) badges.append(element("span", "handoff-badge", answer.optionLabel));
      entry.append(badges);
      if (item.agentInstruction) entry.append(element("p", null, item.agentInstruction));
      if (item.nextAction) entry.append(element("p", null, "다음 행동: " + item.nextAction));
      list.append(entry);
    }
    if (!queue.length) list.append(element("li", "handoff-item", "기록된 피드백이 없습니다."));
    panel.append(list);
    const preview = element("pre", "handoff-prompt");
    preview.id = "handoff-prompt-preview";
    preview.textContent = handoff.resumePrompt || "기록된 피드백이 없습니다.";
    panel.append(preview);
    $("handoff-toggle").textContent = `수집된 피드백 (${queue.length})`;
  }
  function showToast(message) {
    const toast = $("toast");
    toast.textContent = message;
    toast.classList.add("visible");
    window.clearTimeout(showToast.timer);
    showToast.timer = window.setTimeout(() => toast.classList.remove("visible"), 4200);
  }

  async function copyText(value) {
    if (navigator.clipboard?.writeText) {
      await navigator.clipboard.writeText(value);
      return;
    }
    const textarea = document.createElement("textarea");
    textarea.value = value;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.append(textarea);
    textarea.select();
    const copied = document.execCommand("copy");
    textarea.remove();
    if (!copied) throw new Error("copy failed");
  }

  async function saveDecision(group, action, note, choice = {}) {
    const button = [...document.querySelectorAll(".decision-actions button")].find((item) => item.textContent.includes(action === "approve" ? "승인" : action === "request_changes" ? "수정" : action === "add_info" ? "정보" : "보류"));
    if (button) button.disabled = true;
    try {
      const response = await fetch("/api/decisions", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ groupId: group.id, action, note, decisionId: choice.decisionId || null, optionId: choice.optionId || null }) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "결정을 저장하지 못했습니다.");
      showToast(data.message || "결정이 기록되었습니다.");
      await loadReport(group.id);
    } catch (error) {
      showToast(error instanceof Error ? error.message : "결정을 저장하지 못했습니다.");
    } finally {
      if (button) button.disabled = false;
    }
  }

  async function fetchJson(url) {
    const response = await fetch(url, { cache: "no-store" });
    if (!response.ok) throw new Error(`${url} 요청에 실패했습니다.`);
    return response.json();
  }

  async function loadReport(preferredId) {
    try {
      const [reportResult, handoffResult] = await Promise.allSettled([fetchJson("/api/report"), fetchJson("/api/handoff")]);
      if (reportResult.status === "rejected") throw reportResult.reason;
      state.report = reportResult.value;
      state.handoff = handoffResult.status === "fulfilled" ? handoffResult.value : null;
      updateSummary();
      renderAreas();
      renderHarnesses();
      const nextId = preferredId || state.selectedId || state.report.groups[0]?.id;
      renderList();
      const selected = state.report.groups.find((group) => group.id === state.selectedId);
      if (selected) renderDetail(selected);
      renderAudit();
      renderHandoff();
    } catch (error) {
      $("list-status").textContent = error instanceof Error ? error.message : "보고서를 불러오지 못했습니다.";
    }
  }

  function syncFilterControls() {
    $("needs-decision-only").checked = state.needsDecisionOnly;
    $("show-completed").checked = state.statuses.has("completed");
    document.querySelectorAll('input[name="activity"]').forEach((input) => { input.checked = state.activities.has(input.value); });
    document.querySelectorAll('input[name="status"]').forEach((input) => { input.checked = state.statuses.has(input.value); });
    document.querySelectorAll('input[name="priority"]').forEach((input) => { input.checked = state.priorities.has(input.value); });
  }

  function jumpToNextUndecided() {
    const candidates = (state.report?.groups || []).filter((group) => group.needsDecision === true);
    if (!candidates.length) {
      showToast("결정이 필요한 그룹이 없습니다.");
      return;
    }
    state.needsDecisionOnly = true;
    state.search = "";
    state.areas.clear();
    state.harnesses.clear();
    state.activities = new Set(["working", "idle"]);
    state.statuses = new Set(DEFAULT_STATUSES);
    state.priorities = new Set(["high", "normal", "low"]);
    $("search").value = "";
    syncFilterControls();
    renderAreas();
    renderHarnesses();
    const currentIndex = candidates.findIndex((group) => group.id === state.selectedId);
    const target = candidates[(currentIndex + 1) % candidates.length];
    selectGroup(target, true);
  }

  function moveSelection(offset) {
    const rows = [...$("group-list").querySelectorAll(".group-row")];
    if (!rows.length) return;
    const current = rows.findIndex((row) => row.dataset.groupId === state.selectedId);
    const targetRow = rows[(current + offset + rows.length) % rows.length];
    const group = state.report.groups.find((item) => item.id === targetRow.dataset.groupId);
    if (group) selectGroup(group, true);
  }
  async function submitFeedback() {
    const button = $("submit-feedback");
    if (button) button.disabled = true;
    try {
      const response = await fetch("/api/submit", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({}) });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "피드백을 제출하지 못했습니다.");
      showToast(data.message || "피드백이 제출되었습니다.");
      await loadReport(state.selectedId);
    } catch (error) {
      showToast(error instanceof Error ? error.message : "피드백을 제출하지 못했습니다.");
    } finally {
      if (button) button.disabled = false;
    }
  }

  $("submit-feedback").addEventListener("click", submitFeedback);
  $("refresh-report").addEventListener("click", async () => {
    const button = $("refresh-report");
    button.disabled = true;
    try { await loadReport(state.selectedId); } finally { button.disabled = false; }
  });
  $("search").addEventListener("input", (event) => { state.search = event.target.value; renderList(); });
  $("needs-decision-only").addEventListener("change", (event) => { state.needsDecisionOnly = event.target.checked; renderList(); });
  document.querySelectorAll('input[name="activity"]').forEach((input) => input.addEventListener("change", () => {
    state.activities = new Set([...document.querySelectorAll('input[name="activity"]:checked')].map((item) => item.value));
    renderList();
  }));
  document.querySelectorAll('input[name="status"]').forEach((input) => input.addEventListener("change", () => {
    state.statuses = new Set([...document.querySelectorAll('input[name="status"]:checked')].map((item) => item.value));
    renderList();
  }));
  document.querySelectorAll('input[name="priority"]').forEach((input) => input.addEventListener("change", () => {
    state.priorities = new Set([...document.querySelectorAll('input[name="priority"]:checked')].map((item) => item.value));
    renderList();
  }));
  $("next-undecided").addEventListener("click", jumpToNextUndecided);
  $("clear-filters").addEventListener("click", () => {
    state.search = "";
    state.areas.clear();
    state.harnesses.clear();
    state.activities = new Set(["working", "idle"]);
    state.statuses = new Set(DEFAULT_STATUSES);
    state.priorities = new Set(["high", "normal", "low"]);
    state.needsDecisionOnly = false;
    $("search").value = "";
    syncFilterControls();
    renderAreas();
    renderHarnesses();
    renderList();
  });
  document.querySelectorAll(".theme-option").forEach((button) => button.addEventListener("click", () => applyTheme(button.dataset.themeOption, true)));
  if (window.matchMedia) {
    const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");
    if (typeof darkQuery.addEventListener === "function") darkQuery.addEventListener("change", () => { if (state.themeMode === "system") applyTheme("system", false); });
  }
  $("audit-toggle").addEventListener("click", () => {
    const panel = $("audit-panel");
    const opening = panel.hidden;
    closeDrawers();
    panel.hidden = !opening;
    $("audit-toggle").setAttribute("aria-expanded", String(opening));
    if (opening) panel.scrollTop = 0;
  });
  $("handoff-toggle").addEventListener("click", () => {
    const panel = $("handoff-panel");
    const opening = panel.hidden;
    closeDrawers();
    panel.hidden = !opening;
    $("handoff-toggle").setAttribute("aria-expanded", String(opening));
    if (opening) panel.scrollTop = 0;
  });
  document.addEventListener("keydown", (event) => {
    if (event.target instanceof HTMLElement && ["INPUT", "TEXTAREA", "SELECT"].includes(event.target.tagName)) return;
    if (event.key === "j") { event.preventDefault(); moveSelection(1); }
    if (event.key === "k") { event.preventDefault(); moveSelection(-1); }
    if (event.key === "n") { event.preventDefault(); jumpToNextUndecided(); }
    if (event.key === "h") { event.preventDefault(); $("handoff-toggle").click(); }
  });
  applyTheme(readInitialThemeMode(), false);
  loadReport();
})();
