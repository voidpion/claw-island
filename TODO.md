# TODO

- [ ] Hook 注册健康检查：app 运行期间定时（如 30s）检查 `~/.claude/settings.json` 中 hooks 是否存在，丢失则自动补注册。防止被其他工具（插件等）覆盖 settings.json 后 hooks 丢失。
