import Foundation

enum TabletCatalog {
    static let all: [TabletDefinition] = [
        t("chivalry", "기사도", "common", "slabs/chivalry.png", true),
        t("dry", "건조", "common", "slabs/dry.png"),
        t("approximation", "근사", "common", "slabs/approximation.png", true),
        t("advent", "도래", "common", "slabs/advent.png", true),
        t("linear", "선의", "common", "slabs/linear.png"),
        t("sight", "시선", "common", "slabs/sight.png", true),
        t("handshake", "악수", "common", "slabs/handshake.png", true),
        t("fate", "운명", "common", "slabs/fate.webp"),
        t("wit", "재치", "common", "slabs/wit.png", true),
        t("exploitation", "착취", "common", "slabs/exploitation.png", true),
        t("unity", "화합", "common", "slabs/unity.png", true),
        t("cheer", "환호", "common", "slabs/cheer.webp"),
        t("hope", "희망", "common", "slabs/hope.png", true),
        t("nurture", "양육", "common", "slabs/nurture.png", true),
        t("joke", "장난", "common", "slabs/joke.png", true),
        t("compete", "경쟁", "advanced", "slabs/compete.png", true),
        t("beating", "고동", "advanced", "slabs/beating.png", true),
        t("home_town", "고양", "advanced", "slabs/home-town.png", true),
        t("past", "과거", "advanced", "slabs/past.png", true),
        t("future", "미래", "advanced", "slabs/future.png", true),
        t("distribution", "분배", "advanced", "slabs/distribution.png"),
        t("triceps", "삼두", "advanced", "slabs/triceps.png"),
        t("harvesting", "수확", "advanced", "slabs/harvesting.png", true),
        t("binary_star", "쌍성", "advanced", "slabs/binary_star.png", true),
        t("yearning", "열망", "advanced", "slabs/yearning.png"),
        t("agglutination", "응집", "advanced", "slabs/agglutination.png", true),
        t("entrance", "입구", "advanced", "slabs/entrance.png"),
        t("load", "적재", "advanced", "slabs/load.png", true),
        t("transition", "전이", "advanced", "slabs/transition.png", true),
        t("advance", "전진", "advanced", "slabs/advance.png", true),
        t("justice", "정의", "advanced", "slabs/justice.png"),
        t("preparation", "준비", "advanced", "slabs/preparation.png", true),
        t("exit", "출구", "advanced", "slabs/exit.png"),
        t("tide", "파도", "advanced", "slabs/tide.png", true),
        t("dedication", "헌정", "advanced", "slabs/dedication.png"),
        t("honor", "명예", "advanced", "slabs/honor.png", true),
        t("rally", "집결", "advanced", "slabs/rally.png", true),
        t("development", "발전", "advanced", "slabs/development.png", true),
        t("base", "기반", "rare", "slabs/base.png"),
        t("warrant", "권능", "rare", "slabs/warrant.png", true),
        t("disconnection", "단절", "rare", "slabs/disconnection.png"),
        t("concurrency", "동시성", "rare", "slabs/concurrency.png"),
        t("vow", "맹세", "rare", "slabs/vow.png", true),
        t("rebellion", "반항", "rare", "slabs/rebellion.png", true),
        t("connection", "이음", "rare", "slabs/connection.png", true),
        t("junction", "접합", "rare", "slabs/junction.png", true),
        t("last_stand", "배수진", "rare", "slabs/last_stand.png"),
        t("flag", "깃발", "rare", "slabs/flag.png"),
        t("defender", "방어수", "rare", "slabs/defender.png"),
        t("shade", "차양", "rare", "slabs/shade.png"),
        t("wedge", "쐐기", "rare", "slabs/wedge.png", true),
        t("thorn", "가시", "legend", "slabs/thorn.png"),
        t("boundary", "경계", "legend", "slabs/boundary.png"),
        t("sheen", "광휘", "legend", "slabs/sheen.png", true),
        t("miracle", "기적", "legend", "slabs/miracle.png"),
        t("daydream", "백일몽", "legend", "slabs/daydream.png", true),
        t("compression", "압축", "legend", "slabs/compression.png", true),
        t("certitude", "확신", "legend", "slabs/certitude.png", true),
        t("hospitality", "환대", "legend", "slabs/hospitality.png"),
        t("courage", "용기", "legend", "slabs/courage.png", true),
        t("peace", "평화", "legend", "slabs/peace.png", true)
    ]

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    private static func t(
        _ id: String,
        _ name: String,
        _ tier: String,
        _ image: String,
        _ rotatable: Bool = false
    ) -> TabletDefinition {
        TabletDefinition(id: id, koreanName: name, tier: tier, imagePath: image, isRotatable: rotatable)
    }
}
