import Foundation

enum PluginDecoding {
    static func pluginsPage(from data: Data) -> PluginsPage? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let catalogue = (object["catalogue"] as? [[String: Any]] ?? []).compactMap(catalogueItem)
        let servers = (object["servers"] as? [[String: Any]] ?? []).compactMap(server)
        let skills = (object["skills"] as? [[String: Any]] ?? []).compactMap(skill)
        return PluginsPage(
            catalogue: catalogue,
            servers: servers,
            skills: skills,
            botsMayCallBack: object["botsMayCallBack"] as? Bool ?? false,
            redirectURI: object["redirectUri"] as? String
        )
    }

    static func grantedPlugins(from data: Data) -> GrantedPlugins? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let tools = (object["tools"] as? [[String: Any]] ?? []).compactMap { row -> GrantedPlugins.GrantedTool? in
            guard let ref = row["ref"] as? String else { return nil }
            return GrantedPlugins.GrantedTool(
                ref: ref,
                toolName: row["toolName"] as? String ?? ref,
                summary: row["description"] as? String ?? ""
            )
        }
        let skills = (object["skills"] as? [[String: Any]] ?? []).compactMap { row -> GrantedPlugins.GrantedSkill? in
            guard let slug = row["slug"] as? String else { return nil }
            return GrantedPlugins.GrantedSkill(
                slug: slug,
                title: row["title"] as? String ?? slug,
                summary: row["summary"] as? String ?? "",
                instructions: row["instructions"] as? String ?? ""
            )
        }
        return GrantedPlugins(tools: tools, skills: skills)
    }

    private static func catalogueItem(from row: [String: Any]) -> CatalogueItem? {
        guard
            let key = row["key"] as? String,
            let authRaw = row["auth"] as? String,
            let auth = CatalogueItem.AuthKind(rawValue: authRaw)
        else { return nil }
        return CatalogueItem(
            key: key,
            title: row["title"] as? String ?? key,
            vendor: row["vendor"] as? String ?? "",
            summary: row["summary"] as? String ?? "",
            docsURL: row["docsUrl"] as? String ?? "",
            auth: auth,
            perInstance: row["perInstance"] as? Bool ?? false
        )
    }

    private static func server(from row: [String: Any]) -> PluginServer? {
        guard let id = row["id"] as? String else { return nil }
        let tools = (row["tools"] as? [[String: Any]] ?? []).compactMap(tool)
        return PluginServer(
            id: id,
            title: row["title"] as? String ?? id,
            vendor: row["vendor"] as? String ?? "",
            url: row["url"] as? String ?? "",
            summary: row["summary"] as? String ?? "",
            docsURL: row["docsUrl"] as? String ?? "",
            hasCredential: row["hasCredential"] as? Bool ?? false,
            toolsRefreshedAt: row["toolsRefreshedAt"] as? String,
            lastError: row["lastError"] as? String,
            dynamicClient: row["dynamicClient"] as? Bool ?? false,
            tools: tools
        )
    }

    private static func tool(from row: [String: Any]) -> PluginTool? {
        guard
            let serverID = row["serverId"] as? String,
            let name = row["name"] as? String,
            let ref = row["ref"] as? String
        else { return nil }
        let effectRaw = row["effect"] as? String ?? "write"
        return PluginTool(
            serverID: serverID,
            name: name,
            summary: row["description"] as? String ?? "",
            ref: ref,
            effect: PluginTool.Effect(rawValue: effectRaw) ?? .write,
            grantedTo: row["grantedTo"] as? [String] ?? []
        )
    }

    private static func skill(from row: [String: Any]) -> PluginSkill? {
        guard let id = row["id"] as? String, let slug = row["slug"] as? String else { return nil }
        return PluginSkill(
            id: id,
            slug: slug,
            title: row["title"] as? String ?? slug,
            summary: row["summary"] as? String ?? "",
            instructions: row["instructions"] as? String ?? "",
            grantedTo: row["grantedTo"] as? [String] ?? [],
            tools: row["tools"] as? [String] ?? []
        )
    }
}
