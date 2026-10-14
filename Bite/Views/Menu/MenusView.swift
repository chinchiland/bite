import SwiftUI

/// Every menu you photographed, newest first. A swipe deletes one; what you logged from it stays.
struct MenusView: View {
    var body: some View {
        List {
            Section {
                ForEach(MenuShelf.shared.menus) { menu in
                    NavigationLink(value: FoodRoute.menu(menu.id)) {
                        MenuRow(menu: menu)
                    }
                    .listRowBackground(Theme.card)
                }
                .onDelete { offsets in
                    let ids = offsets.map { MenuShelf.shared.menus[$0].id }
                    for id in ids { MenuShelf.shared.remove(id) }
                }
            } footer: {
                Text("Kept on this phone. What you logged from a menu stays when you delete it.")
                    .font(.ui(13))
                    .foregroundStyle(Theme.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.page.ignoresSafeArea())
        .navigationTitle("Your menus")
        .navigationBarTitleDisplayMode(.inline)
    }
}
