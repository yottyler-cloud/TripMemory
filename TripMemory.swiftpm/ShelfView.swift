import SwiftUI

// アプリの入り口：本棚と旅ノートを切り替える
struct RootView: View {
    @ObservedObject private var store = TripStore.shared
    @State private var openTripID: UUID?

    var body: some View {
        Group {
            if let id = openTripID, store.trip(id) != nil {
                NotebookView(tripID: id, onClose: { openTripID = nil })
            } else {
                ShelfView(onOpen: { openTripID = $0 })
            }
        }
        .preferredColorScheme(.dark)
    }
}

// 本棚：旅ごとに1冊のノートが並ぶ
struct ShelfView: View {
    let onOpen: (UUID) -> Void

    @ObservedObject private var store = TripStore.shared
    @State private var singleEdit = false
    @State private var deleting: Trip?

    var visitedCount: Int {
        Set(store.trips.flatMap { $0.prefectures }).count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("TripMemory")
                    .font(.title2.bold())
                Text("旅ノート \(store.trips.count)冊　・　行った県 \(visitedCount) / 47")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    singleEdit = true
                } label: {
                    Label("写真1枚だけ編集", systemImage: "photo")
                }
                .buttonStyle(.bordered)
                Text("v\(appVersion)").font(.caption).foregroundStyle(.gray)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color(white: 0.09))

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 260), spacing: 28)], spacing: 28) {
                    Button {
                        let t = store.newTrip()
                        onOpen(t.id)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 40, weight: .light))
                            Text("新しい旅")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 290)
                        .foregroundStyle(Color(white: 0.8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                                .foregroundStyle(Color(white: 0.45))
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    ForEach(store.trips) { trip in
                        Button {
                            onOpen(trip.id)
                        } label: {
                            TripCover(trip: trip)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) {
                                deleting = trip
                            } label: {
                                Label("このノートを削除", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(28)

                Text("ノートを長押しすると削除できます")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 24)
            }
        }
        .foregroundStyle(.white)
        .background(Color(white: 0.16).ignoresSafeArea())
        .fullScreenCover(isPresented: $singleEdit) {
            ContentView(onClose: { singleEdit = false })
        }
        .confirmationDialog("このノートを削除しますか？",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                if let d = deleting { store.delete(d) }
                deleting = nil
            }
            Button("やめる", role: .cancel) { deleting = nil }
        } message: {
            Text("ノートの中の写真や手書きメモも消えます。写真アプリの元の写真は消えません。")
        }
    }
}

// ノートの表紙
struct TripCover: View {
    let trip: Trip

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.black.opacity(0.25))
                .frame(width: 10)
            VStack(alignment: .leading, spacing: 8) {
                Text(trip.title)
                    .font(.system(size: 24, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if !trip.dateRangeText.isEmpty {
                    Text(trip.dateRangeText)
                        .font(.footnote)
                        .opacity(0.85)
                }
                Spacer()
                Text("写真 \(trip.photos.count)枚")
                    .font(.footnote)
                    .opacity(0.85)
            }
            .padding(.leading, 18)
            .padding(.trailing, 14)
            .padding(.vertical, 20)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 290)
        .foregroundStyle(.white)
        .background(trip.coverColor)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 3, bottomLeadingRadius: 3,
                                          bottomTrailingRadius: 10, topTrailingRadius: 10))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 5)
    }
}
