import tkinter as tk
from tkinter import ttk, messagebox
import calendar
from datetime import datetime, date
import json
import os
import ctypes
import shutil
from decimal import Decimal, InvalidOperation
from tkinter import font

class BudgetCalendar:
    def __init__(self, root):
        self.root = root
        base_dir = os.path.dirname(os.path.abspath(__file__))
        self.icon_path = os.path.join(base_dir, "icon.ico")
        appdata_dir = os.getenv("APPDATA")
        self.data_dir = os.path.join(appdata_dir, "BudgetCalendar") if appdata_dir else base_dir
        os.makedirs(self.data_dir, exist_ok=True)
        self.data_file = os.path.join(self.data_dir, "budget_data.json")
        legacy_data_file = os.path.join(base_dir, "budget_data.json")
        if not os.path.exists(self.data_file) and os.path.exists(legacy_data_file):
            shutil.copy2(legacy_data_file, self.data_file)

        self.root.title("Budget Calendar")
        self.set_window_icon(self.root)

        # Set a fixed window size
        self.root.geometry("600x600")
        self.root.resizable(False, False)

        self.year = datetime.now().year
        self.month = datetime.now().month
        self.dark_mode = False
        self.theme_colors = {
            "btn_default_bg": "SystemButtonFace",
            "btn_default_fg": "black",
            "btn_hover_bg": "#e0e0e0",
            "btn_hover_fg": "black",
            "income_bg": "#98FB98",
            "expense_bg": "#FFCCCB",
            "both_bg": "#FFFFE0",
            "entry_bg": "white",
            "entry_fg": "black",
        }

        # Load saved data or initialize data
        self.load_data()

        self.dark_mode = bool(self.data.get("settings", {}).get("dark_mode", False))

        # Create the UI components
        self.create_widgets()
        self.apply_theme()
        if self.dark_mode:
            self.root.after(0, lambda: self.set_titlebar_dark(self.root, True))
            self.root.after(150, lambda: self.set_titlebar_dark(self.root, True))

    def create_widgets(self):
        # Frame for Month Label and Navigation Buttons
        self.header_frame = ttk.Frame(self.root)
        self.header_frame.pack(padx=10, pady=10, fill='x')

        # Previous and Next buttons for navigating months
        self.prev_button = ttk.Button(self.header_frame, text="<< Previous", command=self.prev_month, width=12)
        self.prev_button.pack(side='left', padx=5)

        self.next_button = ttk.Button(self.header_frame, text="Next >>", command=self.next_month, width=12)
        self.next_button.pack(side='right', padx=5)

        # Month and Year display
        self.month_label = ttk.Label(self.header_frame, text=f"{calendar.month_name[self.month]} {self.year}", font=("Helvetica", 16))
        self.month_label.pack(pady=10)

        # Frame to hold the calendar (days grid)
        self.calendar_frame = ttk.Frame(self.root)
        self.calendar_frame.pack(padx=10, pady=10, fill='both', expand=True)

        # Frame for displaying the current month's expenses, income, and balance
        self.info_frame = ttk.Frame(self.root)
        self.info_frame.pack(padx=10, pady=10, fill='x')

        self.expense_label = ttk.Label(self.info_frame, text="Current Month's Expenses:")
        self.expense_label.grid(row=0, column=0, padx=5, pady=(10, 5), sticky='w')

        self.expense_var = tk.StringVar(value=self.format_currency(Decimal("0")))
        self.expense_value = tk.Label(self.info_frame, textvariable=self.expense_var, width=20, background="light grey")
        self.expense_value.grid(row=0, column=1, padx=5, pady=(10, 5), sticky='w')

        self.income_label = ttk.Label(self.info_frame, text="Current Month's Income:")
        self.income_label.grid(row=1, column=0, padx=5, pady=(5, 5), sticky='w')

        self.income_var = tk.StringVar(value=self.format_currency(Decimal("0")))
        self.income_value = tk.Label(self.info_frame, textvariable=self.income_var, width=20, background="light grey")
        self.income_value.grid(row=1, column=1, padx=5, pady=(5, 5), sticky='w')

        self.balance_label = ttk.Label(self.info_frame, text="Month's Balance:")
        self.balance_label.grid(row=2, column=0, padx=5, pady=(5, 5), sticky='w')

        self.balance_var = tk.StringVar(value=self.format_currency(Decimal("0")))
        self.balance_value = tk.Label(self.info_frame, textvariable=self.balance_var, width=20, background="light grey")
        self.balance_value.grid(row=2, column=1, padx=5, pady=(5, 5), sticky='w')

        self.running_balance_label = ttk.Label(self.info_frame, text="Total Running Balance:")
        self.running_balance_label.grid(row=3, column=0, padx=5, pady=(5, 10), sticky='w')

        self.running_balance_var = tk.StringVar(value=self.format_currency(Decimal("0")))
        self.running_balance_value = tk.Label(self.info_frame, textvariable=self.running_balance_var, width=20, background="light grey")
        self.running_balance_value.grid(row=3, column=1, padx=5, pady=(5, 10), sticky='w')

        self.dark_mode_button = tk.Button(self.root, text="💡", width=2, height=1, command=self.toggle_dark_mode, bd=0, highlightthickness=0)
        self.dark_mode_button.place(relx=1.0, rely=1.0, anchor="se", x=-6, y=-6)
        self.dark_mode_button.bind("<Enter>", lambda event: self.show_dark_mode_tooltip())
        self.dark_mode_button.bind("<Leave>", lambda event: self.hide_tooltip())

        # Create the calendar for the current month
        self.create_calendar()

    def create_calendar(self):
        # Clear any previous calendar widgets in the calendar frame
        for widget in self.calendar_frame.winfo_children():
            widget.destroy()

        # Get calendar data for the current month
        cal = calendar.monthcalendar(self.year, self.month)

        # Get the current day, month, and year
        current_day = datetime.now().day
        current_month = datetime.now().month
        current_year = datetime.now().year

        # Define a font with italic and underline for the current day
        italic_underline_font = font.Font(slant="italic", underline=1, weight="bold")
        normal_font = font.Font(weight="normal")

        # Create calendar labels for days of the week
        days_of_week = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        for i, day in enumerate(days_of_week):
            ttk.Label(self.calendar_frame, text=day).grid(row=0, column=i, padx=30, pady=5, sticky='nsew')

        # Create the calendar grid
        for r, week in enumerate(cal, start=1):
            for c, day in enumerate(week):
                if day != 0:
                    day_key = f"{self.year}-{self.month:02d}-{day:02d}"
                    income_list = self.data['income'].get(day_key, [])
                    expense_list = self.data['expenses'].get(day_key, [])

                    if not isinstance(income_list, list):
                        income_list = []
                    if not isinstance(expense_list, list):
                        expense_list = []

                    has_income = any(item['amount'] > 0 for item in income_list)
                    has_expense = any(item['amount'] > 0 for item in expense_list)

                    default_btn_bg = self.theme_colors.get("btn_default_bg", "SystemButtonFace")
                    default_btn_fg = self.theme_colors.get("btn_default_fg", "black")
                    income_bg = self.theme_colors.get("income_bg", "#98FB98")
                    expense_bg = self.theme_colors.get("expense_bg", "#FFCCCB")
                    both_bg = self.theme_colors.get("both_bg", "#FFFFE0")

                    if has_income and not has_expense:
                        btn_color = income_bg
                    elif has_expense and not has_income:
                        btn_color = expense_bg
                    elif has_income and has_expense:
                        btn_color = both_bg
                    else:
                        btn_color = default_btn_bg

                    # Check if this is the current day and apply italic+underline style
                    if day == current_day and self.month == current_month and self.year == current_year:
                        btn = tk.Button(self.calendar_frame, text=str(day), bg=btn_color, fg=default_btn_fg, font=italic_underline_font, width=3,
                                        command=lambda d=day: self.show_day_entry(d))
                    else:
                        btn = tk.Button(self.calendar_frame, text=str(day), bg=btn_color, fg=default_btn_fg, font=normal_font, width=3,
                                        command=lambda d=day: self.show_day_entry(d))

                    # Add hover effect to display running balance for the hovered date
                    btn.bind("<Enter>", lambda event, d=day: self.show_running_balance(d))

                    btn.grid(row=r, column=c, padx=5, pady=5, sticky='nsew')

        # Configure column and row weights to ensure proper alignment
        for i in range(7):
            self.calendar_frame.grid_columnconfigure(i, weight=1)  # Makes all columns equal width
        for i in range(len(cal) + 1):
            self.calendar_frame.grid_rowconfigure(i, weight=1)  # Makes all rows equal height

        # Update totals for income, expenses, balance, and running balance
        self.update_totals()

    def show_running_balance(self, day):
        """Show the running balance when hovering over a day."""
        hover_date = date(self.year, self.month, day)
        running_balance = self.calculate_running_balance(hover_date)
        self.running_balance_var.set(self.format_currency(running_balance))


    def show_day_entry(self, day):
        day_key = f"{self.year}-{self.month:02d}-{day:02d}"
        income_list = self.data['income'].get(day_key, [])
        expense_list = self.data['expenses'].get(day_key, [])

        if not isinstance(income_list, list):
            income_list = []
        if not isinstance(expense_list, list):
            expense_list = []

        # Destroy existing entry window if any
        if hasattr(self, 'day_entry_window') and self.day_entry_window.winfo_exists():
            self.day_entry_window.destroy()

        self.day_entry_window = tk.Toplevel(self.root)
        self.day_entry_window.title(f"Entries for {self.month}/{day}/{self.year}")
        self.set_window_icon(self.day_entry_window)

        # Frame for income entries
        income_frame = ttk.Frame(self.day_entry_window)
        income_frame.pack(pady=10, fill='x')

        ttk.Label(income_frame, text="Income Entries:").pack(pady=5)
        self.income_entries = []

        for i, entry in enumerate(income_list):
            entry_frame = ttk.Frame(income_frame)
            entry_frame.pack(pady=2, fill='x')
            ttk.Label(entry_frame, text=f"{entry.get('name', '')}: {self.format_currency(Decimal(str(entry.get('amount', 0))))}").pack(side='left', padx=(6, 0))
            edit_button = ttk.Button(entry_frame, text="Edit", width=5, command=lambda idx=i: self.edit_entry(day_key, 'income', idx))
            edit_button.pack(side='right', padx=5)
            delete_button = ttk.Button(entry_frame, text="Delete", width=6, command=lambda idx=i: self.delete_entry(day_key, 'income', idx))
            delete_button.pack(side='right')

        # Frame for expense entries
        expense_frame = ttk.Frame(self.day_entry_window)
        expense_frame.pack(pady=10, fill='x')

        ttk.Label(expense_frame, text="Expense Entries:").pack(pady=5)
        self.expense_entries = []

        for i, entry in enumerate(expense_list):
            entry_frame = ttk.Frame(expense_frame)
            entry_frame.pack(pady=2, fill='x')
            ttk.Label(entry_frame, text=f"{entry.get('name', '')}: {self.format_currency(Decimal(str(entry.get('amount', 0))))}").pack(side='left', padx=(6, 0))
            edit_button = ttk.Button(entry_frame, text="Edit", width=5, command=lambda idx=i: self.edit_entry(day_key, 'expenses', idx))
            edit_button.pack(side='right', padx=5)
            delete_button = ttk.Button(entry_frame, text="Delete", width=6, command=lambda idx=i: self.delete_entry(day_key, 'expenses', idx))
            delete_button.pack(side='right')

        # Add new income and expense entries
        ttk.Button(self.day_entry_window, text="Add Income", command=lambda: self.add_entry(day_key, 'income')).pack(pady=5)
        ttk.Button(self.day_entry_window, text="Add Expense", command=lambda: self.add_entry(day_key, 'expenses')).pack(pady=5)
        self.apply_popup_theme(self.day_entry_window)
        self.position_popup(self.day_entry_window)

    def add_entry(self, day_key, entry_type):
        def save_entry():
            name = name_entry.get()
            try:
                amount = self.parse_amount(amount_entry.get())
            except (InvalidOperation, ValueError):
                messagebox.showerror("Invalid Amount", "Please enter a valid number for the amount.")
                return

            if not name:
                messagebox.showerror("Missing Name", "Please enter a name for the entry.")
                return

            if entry_type not in self.data:
                self.data[entry_type] = {}

            if day_key not in self.data[entry_type]:
                self.data[entry_type][day_key] = []

            self.data[entry_type][day_key].append({'name': name, 'amount': float(amount)})
            self.save_data()
            self.update_calendar()  # Update calendar after saving
            if hasattr(self, 'add_entry_window') and self.add_entry_window.winfo_exists():
                self.add_entry_window.destroy()  # Properly close the window
            self.show_day_entry(int(day_key[-2:]))

        # Close any existing entry window before opening a new one
        if hasattr(self, 'add_entry_window') and self.add_entry_window.winfo_exists():
            self.add_entry_window.destroy()

        # Create the new entry window
        self.add_entry_window = tk.Toplevel(self.root)
        self.add_entry_window.title(f"Add {entry_type.capitalize()} Entry")
        self.set_window_icon(self.add_entry_window)
        self.position_popup(self.add_entry_window, width=240, height=180)

        ttk.Label(self.add_entry_window, text="Name:").pack(pady=5)
        name_entry = tk.Entry(self.add_entry_window)
        name_entry.pack(pady=5)

        ttk.Label(self.add_entry_window, text="Amount:").pack(pady=5)
        amount_entry = tk.Entry(self.add_entry_window)
        amount_entry.pack(pady=5)

        ttk.Button(self.add_entry_window, text="Save", command=save_entry).pack(pady=10)
        self.apply_popup_theme(self.add_entry_window)

    def edit_entry(self, day_key, entry_type, entry_index):
        entry = self.data[entry_type][day_key][entry_index]
        def save_changes():
            name = name_entry.get()
            try:
                amount = self.parse_amount(amount_entry.get())
            except (InvalidOperation, ValueError):
                messagebox.showerror("Invalid Amount", "Please enter a valid number for the amount.")
                return

            if not name:
                messagebox.showerror("Missing Name", "Please enter a name for the entry.")
                return

            self.data[entry_type][day_key][entry_index] = {'name': name, 'amount': float(amount)}
            self.save_data()
            self.update_calendar()  # Update calendar after saving
            if hasattr(self, 'edit_entry_window') and self.edit_entry_window.winfo_exists():
                self.edit_entry_window.destroy()  # Properly close the window
            self.show_day_entry(int(day_key[-2:]))

        # Close any existing entry window before opening a new one
        if hasattr(self, 'edit_entry_window') and self.edit_entry_window.winfo_exists():
            self.edit_entry_window.destroy()

        # Create the edit entry window
        self.edit_entry_window = tk.Toplevel(self.root)
        self.edit_entry_window.title(f"Edit {entry_type.capitalize()} Entry")
        self.set_window_icon(self.edit_entry_window)
        self.position_popup(self.edit_entry_window, width=240, height=180)

        ttk.Label(self.edit_entry_window, text="Name:").pack(pady=5)
        name_entry = tk.Entry(self.edit_entry_window)
        name_entry.insert(0, entry.get('name', ''))
        name_entry.pack(pady=5)

        ttk.Label(self.edit_entry_window, text="Amount:").pack(pady=5)
        amount_entry = tk.Entry(self.edit_entry_window)
        amount_entry.insert(0, f"{entry['amount']:.2f}")
        amount_entry.pack(pady=5)

        ttk.Button(self.edit_entry_window, text="Save Changes", command=save_changes).pack(pady=10)
        self.apply_popup_theme(self.edit_entry_window)

    def delete_entry(self, day_key, entry_type, entry_index):
        if messagebox.askyesno("Confirm Deletion", "Are you sure you want to delete this entry?"):
            del self.data[entry_type][day_key][entry_index]
            if not self.data[entry_type][day_key]:
                del self.data[entry_type][day_key]
            self.save_data()
            self.update_calendar()  # Update calendar after deleting
            self.show_day_entry(int(day_key[-2:]))

    def update_totals(self):
        month_start = date(self.year, self.month, 1)
        month_end = self.last_day_of_month(self.year, self.month)

        current_month_income = self.sum_entries_in_range('income', month_start, month_end)
        current_month_expenses = self.sum_entries_in_range('expenses', month_start, month_end)
        running_balance = self.calculate_running_balance(month_end)
        current_balance = current_month_income - current_month_expenses

        self.income_var.set(self.format_currency(current_month_income))
        self.expense_var.set(self.format_currency(current_month_expenses))
        self.balance_var.set(self.format_currency(current_balance))
        self.running_balance_var.set(self.format_currency(running_balance))

    def prev_month(self):
        if self.month == 1:
            self.month = 12
            self.year -= 1
        else:
            self.month -= 1
        self.update_calendar()

    def next_month(self):
        if self.month == 12:
            self.month = 1
            self.year += 1
        else:
            self.month += 1
        self.update_calendar()

    def update_calendar(self):
        # Update the month label
        self.month_label.config(text=f"{calendar.month_name[self.month]} {self.year}")
        self.create_calendar()

    def save_data(self):
        with open(self.data_file, 'w') as f:
            json.dump(self.data, f)

    def load_data(self):
        if os.path.exists(self.data_file):
            try:
                with open(self.data_file, 'r') as f:
                    self.data = json.load(f)
            except json.JSONDecodeError:
                messagebox.showwarning('Data Error', 'The data file is corrupted. Starting with empty data.')
                self.data = {'income': {}, 'expenses': {}}
        else:
            self.data = {'income': {}, 'expenses': {}}
            self.save_data()

        if not isinstance(self.data, dict):
            self.data = {'income': {}, 'expenses': {}}
        self.data.setdefault('income', {})
        self.data.setdefault('expenses', {})
        self.data.setdefault('settings', {})

        if not isinstance(self.data.get('income'), dict):
            self.data['income'] = {}
        if not isinstance(self.data.get('expenses'), dict):
            self.data['expenses'] = {}
        if not isinstance(self.data.get('settings'), dict):
            self.data['settings'] = {}

    def parse_date_key(self, date_key):
        try:
            return datetime.strptime(date_key, '%Y-%m-%d').date()
        except ValueError:
            return None

    def toggle_dark_mode(self):
        self.dark_mode = not self.dark_mode
        self.data.setdefault("settings", {})["dark_mode"] = self.dark_mode
        self.save_data()
        self.apply_theme()

    def apply_theme(self):
        self.theme_colors = {}
        if self.dark_mode:
            self.theme_colors.update({
                "root_bg": "#1e1e1e",
                "frame_bg": "#252526",
                "label_fg": "#f0f0f0",
                "btn_default_bg": "#2d2d2d",
                "btn_default_fg": "#f0f0f0",
                "btn_hover_bg": "#3a3a3a",
                "btn_hover_fg": "#f0f0f0",
                "income_bg": "#2d5f2d",
                "expense_bg": "#5f2d2d",
                "both_bg": "#5f5b2d",
                "info_bg": "#2a2a2a",
                "entry_bg": "#1f1f1f",
                "entry_fg": "#f0f0f0",
            })
        else:
            self.theme_colors.update({
                "root_bg": "#f0f0f0",
                "frame_bg": "#f0f0f0",
                "label_fg": "#000000",
                "btn_default_bg": "SystemButtonFace",
                "btn_default_fg": "#000000",
                "btn_hover_bg": "#e0e0e0",
                "btn_hover_fg": "#000000",
                "income_bg": "#98FB98",
                "expense_bg": "#FFCCCB",
                "both_bg": "#FFFFE0",
                "info_bg": "#e0e0e0",
                "entry_bg": "white",
                "entry_fg": "black",
            })

        style = ttk.Style(self.root)
        style.theme_use("clam")
        style.configure("TFrame", background=self.theme_colors["frame_bg"])
        style.configure("TLabel", background=self.theme_colors["frame_bg"], foreground=self.theme_colors["label_fg"])
        style.configure("TButton", background=self.theme_colors["btn_default_bg"], foreground=self.theme_colors["btn_default_fg"])
        style.map(
            "TButton",
            background=[
                ("active", self.theme_colors["btn_hover_bg"]),
                ("pressed", self.theme_colors["btn_default_bg"]),
            ],
            foreground=[
                ("active", self.theme_colors["btn_hover_fg"]),
                ("pressed", self.theme_colors["btn_default_fg"]),
            ],
        )
        style.configure("TEntry", fieldbackground=self.theme_colors["entry_bg"], foreground=self.theme_colors["entry_fg"])
        style.map("TEntry", fieldbackground=[("readonly", self.theme_colors["entry_bg"]), ("disabled", self.theme_colors["entry_bg"])])

        self.root.configure(bg=self.theme_colors["root_bg"])
        self.expense_value.configure(bg=self.theme_colors["info_bg"], fg=self.theme_colors["label_fg"])
        self.income_value.configure(bg=self.theme_colors["info_bg"], fg=self.theme_colors["label_fg"])
        self.balance_value.configure(bg=self.theme_colors["info_bg"], fg=self.theme_colors["label_fg"])
        self.running_balance_value.configure(bg=self.theme_colors["info_bg"], fg=self.theme_colors["label_fg"])

        self.dark_mode_button.configure(
            bg=self.theme_colors["btn_default_bg"],
            fg=self.theme_colors["btn_default_fg"],
            activebackground=self.theme_colors["btn_default_bg"],
            activeforeground=self.theme_colors["btn_default_fg"],
        )
        self.apply_windows_dark_mode(self.dark_mode)
        self.set_titlebar_dark(self.root, self.dark_mode)
        for window_name in ("day_entry_window", "add_entry_window", "edit_entry_window"):
            if hasattr(self, window_name):
                window = getattr(self, window_name)
                if window.winfo_exists():
                    self.apply_popup_theme(window)

        self.update_calendar()

    def apply_popup_theme(self, window):
        window.configure(bg=self.theme_colors["root_bg"])
        window.update_idletasks()
        self.set_titlebar_dark(window, self.dark_mode)
        self.apply_widget_theme(window)
        if self.dark_mode:
            window.after(0, lambda w=window: self.set_titlebar_dark(w, True))
            window.after(100, lambda w=window: self.set_titlebar_dark(w, True))

    def set_window_icon(self, window):
        if os.path.exists(self.icon_path):
            window.iconbitmap(self.icon_path)

    def apply_widget_theme(self, widget):
        for child in widget.winfo_children():
            if isinstance(child, tk.Entry):
                child.configure(
                    bg=self.theme_colors["entry_bg"],
                    fg=self.theme_colors["entry_fg"],
                    insertbackground=self.theme_colors["entry_fg"],
                )
            elif isinstance(child, ttk.Entry):
                child.configure()
            elif isinstance(child, tk.Label):
                child.configure(bg=self.theme_colors["root_bg"], fg=self.theme_colors["label_fg"])
            elif isinstance(child, tk.Button):
                child.configure(
                    bg=self.theme_colors["btn_default_bg"],
                    fg=self.theme_colors["btn_default_fg"],
                    activebackground=self.theme_colors["btn_default_bg"],
                    activeforeground=self.theme_colors["btn_default_fg"],
                )
            elif isinstance(child, tk.Frame):
                child.configure(bg=self.theme_colors["frame_bg"])
            self.apply_widget_theme(child)

    def show_tooltip(self, widget, text):
        self.hide_tooltip()
        tooltip = tk.Toplevel(self.root)
        tooltip.wm_overrideredirect(True)
        tooltip.attributes("-topmost", True)
        x = widget.winfo_rootx() + widget.winfo_width() + 6
        y = widget.winfo_rooty() + widget.winfo_height() // 2
        tooltip.geometry(f"+{x}+{y}")
        label = tk.Label(
            tooltip,
            text=text,
            bg=self.theme_colors.get("frame_bg", "#f0f0f0"),
            fg=self.theme_colors.get("label_fg", "#000000"),
            padx=6,
            pady=2,
        )
        label.pack()
        self._tooltip = tooltip

    def show_dark_mode_tooltip(self):
        text = "Disable dark mode" if self.dark_mode else "Enable dark mode"
        self.show_tooltip(self.dark_mode_button, text)

    def hide_tooltip(self):
        tooltip = getattr(self, "_tooltip", None)
        if tooltip and tooltip.winfo_exists():
            tooltip.destroy()
        self._tooltip = None

    def set_titlebar_dark(self, window, enabled):
        """Attempt to set a window's titlebar to dark mode on Windows."""
        if os.name != "nt":
            return
        try:
            hwnd = window.winfo_id()
            get_parent = ctypes.windll.user32.GetParent
            parent = get_parent(hwnd)
            while parent:
                hwnd = parent
                parent = get_parent(hwnd)
            value = ctypes.c_int(1 if enabled else 0)
            dwmapi = ctypes.windll.dwmapi
            attr = 20
            res = dwmapi.DwmSetWindowAttribute(hwnd, attr, ctypes.byref(value), ctypes.sizeof(value))
            if res != 0:
                attr = 19
                dwmapi.DwmSetWindowAttribute(hwnd, attr, ctypes.byref(value), ctypes.sizeof(value))
        except Exception:
            pass

    def apply_windows_dark_mode(self, enabled):
        if os.name != "nt":
            return
        try:
            uxtheme = ctypes.windll.uxtheme
            set_app_mode = getattr(uxtheme, "SetPreferredAppMode", None)
            refresh = getattr(uxtheme, "RefreshImmersiveColorPolicyState", None)
            if set_app_mode is not None:
                set_app_mode(2 if enabled else 0)
            if refresh is not None:
                refresh()
        except Exception:
            pass

    def position_popup(self, window, width=None, height=None):
        window.update_idletasks()
        req_w = window.winfo_reqwidth()
        req_h = window.winfo_reqheight()
        screen_w = window.winfo_screenwidth()
        screen_h = window.winfo_screenheight()
        width = width or max(240, min(req_w, screen_w - 40))
        height = height or max(200, min(req_h, screen_h - 80))
        root_x = self.root.winfo_rootx()
        root_y = self.root.winfo_rooty()
        root_w = self.root.winfo_width()
        root_h = self.root.winfo_height()
        x = root_x + max((root_w - width) // 2, 0)
        y = root_y + max((root_h - height) // 2, 0)
        window.geometry(f"{width}x{height}+{x}+{y}")

    def parse_amount(self, amount_text):
        return Decimal(amount_text.strip())

    def format_currency(self, amount):
        quantized = amount.quantize(Decimal('0.01'))
        return f"£{quantized:.2f}"

    def last_day_of_month(self, year, month):
        last_day = calendar.monthrange(year, month)[1]
        return date(year, month, last_day)

    def sum_entries_in_range(self, entry_type, start_date, end_date):
        total = Decimal('0')
        for date_key, entries in self.data.get(entry_type, {}).items():
            entry_date = self.parse_date_key(date_key)
            if entry_date is None or entry_date < start_date or entry_date > end_date:
                continue
            for entry in entries if isinstance(entries, list) else []:
                total += Decimal(str(entry.get('amount', 0)))
        return total

    def calculate_running_balance(self, up_to_date):
        running_total = Decimal('0')
        for entry_type, multiplier in (('income', 1), ('expenses', -1)):
            for date_key, entries in self.data.get(entry_type, {}).items():
                entry_date = self.parse_date_key(date_key)
                if entry_date is None or entry_date > up_to_date:
                    continue
                for entry in entries if isinstance(entries, list) else []:
                    running_total += Decimal(str(entry.get('amount', 0))) * multiplier
        return running_total

if __name__ == "__main__":
    root = tk.Tk()
    app = BudgetCalendar(root)
    root.mainloop()
