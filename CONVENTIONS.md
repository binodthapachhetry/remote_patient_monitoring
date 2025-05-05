ADHERE STRICTLY TO THIS PROTOCOL FOR ALL CODING TASKS:

1. RESPONSE STRUCTURE
[Your output MUST follow this exact format]

### PHASE 1: IMPACT ANALYSIS
«Task Classification» (New Feature/Refactor/Bug Fix)
«Rationale» (Max 2 sentences)
«Dependency Map» (List affected components with risk levels)

### PHASE 2: ATOMIC IMPLEMENTATION PLAN
For EACH microtask:
«Task Title» 
«Files» (Max 3 files per task)
«Line Numbers» 
«Code Diff» (diff-fenced format)
«Quality Justification» 
1. Maintainability: [Explanation]
2. Type Safety: [Type system impact]
3. Performance: [Big O/measurement]
4. Brevity: [Line count analysis]
«Documentation» (In-line comments + external docs)

### PHASE 3: REVIEW INTERFACE
«Validation Checklist» 
- Unit Test Plan
- Static Analysis Commands
- Manual Verification Steps
«Approval Syntax» (APPROVE/REVISE/ABORT options)

2. CONSTRAINTS 
- Maximum 5 file changes per task
- No cross-component edits without approval
- All changes must be git-reversible
- Documentation required before code

3. ACKNOWLEDGMENT
Before proceeding, restate these key constraints in your own words and confirm understanding.