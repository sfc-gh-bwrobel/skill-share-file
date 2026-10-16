REPO_URL   := https://github.com/sfc-gh-bwrobel/skill-share-file/tree/main/.cortex/skills/share-file
SOURCE     := github:sfc-gh-bwrobel/skill-share-file
CONFIG     := .cortex/skills/share-file/config.json
CACHE_GLOB := $(HOME)/.snowflake/cortex/remote_cache/github_sfc-gh-bwrobel_skill-share-file_*/main/.cortex/skills/share-file

.PHONY: install uninstall reinstall

install:
	cortex skill add $(REPO_URL)
	@if [ -f $(CONFIG) ]; then \
		for d in $(CACHE_GLOB); do cp $(CONFIG) "$$d/" && echo "Copied config.json to $$d"; done; \
	else \
		echo "No $(CONFIG) found; the skill will ask for its settings on first use."; \
	fi

uninstall:
	@if cortex skill list 2>/dev/null | grep -q "$(SOURCE)"; then \
		cortex skill remove $(SOURCE); \
	else \
		echo "share-file is not installed, nothing to remove."; \
	fi

reinstall: uninstall install
