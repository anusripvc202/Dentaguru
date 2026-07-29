// ==========================================================================
// DENTA GURU WEB SIMULATOR LOGIC
// Rich cross-screen transitions, filters, and mock CRUD events
// ==========================================================================

// 1. DATA STATE MOCKUPS
let patientAppointments = [
    {
        id: "APT-202",
        doctor: "Dr. Sarah Jenkins",
        clinic: "Apex Orthodontics & Implants",
        date: "Oct 23, 2023",
        time: "09:30 AM",
        treatment: "Root Canal Therapy",
        status: "confirmed"
    },
    {
        id: "APT-203",
        doctor: "Dr. Michael Chen",
        clinic: "Smile Craft Dental Care",
        date: "Nov 12, 2023",
        time: "02:00 PM",
        treatment: "Routine Cleaning",
        status: "confirmed"
    }
];

let dentistPatients = [
    {
        id: "DG-901",
        initials: "JS",
        name: "Jane Smith",
        age: 28,
        gender: "Female",
        status: "active",
        procedure: "Teeth Whitening",
        lastVisit: "Oct 12, 2023"
    },
    {
        id: "DG-902",
        initials: "MR",
        name: "Michael Ross",
        age: 45,
        gender: "Male",
        status: "follow-up",
        procedure: "Root Canal",
        lastVisit: "Sep 28, 2023"
    },
    {
        id: "DG-903",
        initials: "AW",
        name: "Alice Wong",
        age: 32,
        gender: "Female",
        status: "inactive",
        procedure: "Checkup",
        lastVisit: "Aug 15, 2023"
    },
    {
        id: "DG-904",
        initials: "DK",
        name: "David Kim",
        age: 19,
        gender: "Male",
        status: "new",
        procedure: "Consultation",
        lastVisit: "Pending"
    }
];

// Active Tag state for filtering
let currentPatientRecordTag = 'all';
let currentDentistPatientTag = 'all';

// 2. MASTER PORTAL NAVIGATION SWITCHER
document.querySelectorAll('.portal-nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        // Toggle nav active
        document.querySelectorAll('.portal-nav-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');

        // Toggle portal viewport active
        const targetView = btn.getAttribute('data-view');
        document.querySelectorAll('.portal-viewport').forEach(view => {
            view.classList.remove('active');
        });
        
        const activeView = document.getElementById(`view-${targetView}`);
        if (activeView) {
            activeView.classList.add('active');
        }

        // Action hooks
        if (targetView === 'patient') {
            renderPatientAppointments();
        } else if (targetView === 'dentist') {
            renderDentistPatients();
        } else if (targetView === 'admin') {
            if (!isAdminLoggedIn) {
                logoutAdminUser();
            }
        }
    });
});

// 3. PATIENT MOBILE PORTAL ROUTING
function switchPatientTab(tabName) {
    // Hide all screens in patient app
    document.querySelectorAll('.patient-screen').forEach(screen => {
        screen.classList.remove('active');
    });
    
    // Show target screen
    const targetScreen = document.getElementById(`p-screen-${tabName}`);
    if (targetScreen) {
        targetScreen.classList.add('active');
    }

    // Toggle footer icons active state
    document.querySelectorAll('.footer-nav-item').forEach(item => {
        item.classList.remove('active');
    });
    const activeIcon = document.querySelector(`[data-ptab-trigger="${tabName}"]`);
    if(activeIcon) activeIcon.classList.add('active');

    // Toggle footer bar visibility based on Auth state
    const footerNav = document.querySelector('.screen-footer-nav');
    if (footerNav) {
        footerNav.style.display = (tabName === 'auth') ? 'none' : 'flex';
    }

    // If appointments screen loaded
    if (tabName === 'appointments') {
        renderPatientAppointments();
    }
}

// Quick Actions dynamic routing
function clickPatientAction(actionType) {
    if (actionType === 'book') {
        switchPatientTab('appointments');
    } else if (actionType === 'find') {
        openFindDentistModal();
    } else if (actionType === 'xrays') {
        switchPatientTab('records');
        setPatientRecordTag('xrays');
    } else if (actionType === 'billing') {
        switchPatientTab('profile');
        showPatientToast("Billing card selected: Visa *4920");
    }
}

function openFindDentistModal() {
    const modal = document.getElementById('find-dentist-modal');
    if (modal) modal.style.display = 'flex';
}

function closeFindDentistModal() {
    const modal = document.getElementById('find-dentist-modal');
    if (modal) modal.style.display = 'none';
}

function selectSpecialistDoctor(docName, treatment) {
    closeFindDentistModal();
    const newApt = {
        id: `APT-${Math.floor(200 + Math.random() * 800)}`,
        doctor: docName,
        clinic: "Apex Orthodontics & Implants",
        date: "Oct 25, 2023",
        time: "10:15 AM",
        treatment: treatment || "Specialist Consultation",
        status: "confirmed"
    };

    patientAppointments.unshift(newApt);
    updatePatientDashboardCard(newApt);
    renderPatientAppointments();
    
    showPatientToast(`Appointment booked with ${docName}!`);
    switchPatientTab('dashboard');
}

// Records Search Engine
function filterPatientRecords() {
    const query = document.getElementById('patient-record-search').value.toLowerCase();
    const summaries = document.querySelectorAll('.record-summary-item');
    const xraysSec = document.getElementById('patient-xrays-section');

    summaries.forEach(item => {
        const text = item.innerText.toLowerCase();
        if (text.includes(query)) {
            item.style.display = 'block';
        } else {
            item.style.display = 'none';
        }
    });

    if (query.includes('scan') || query.includes('xray') || query.includes('molar') || query === '') {
        if(xraysSec) xraysSec.style.display = 'block';
    } else {
        if(xraysSec) xraysSec.style.display = 'none';
    }
}

// Records Tags
function setPatientRecordTag(tag) {
    currentPatientRecordTag = tag;
    document.querySelectorAll('#p-screen-records .filter-tag').forEach(t => t.classList.remove('active'));
    
    const activeTag = document.getElementById(`ptag-${tag}`);
    if (activeTag) activeTag.classList.add('active');

    const summaries = document.querySelectorAll('.record-summary-item');
    const xraysSec = document.getElementById('patient-xrays-section');

    if (tag === 'all') {
        summaries.forEach(i => i.style.display = 'block');
        if(xraysSec) xraysSec.style.display = 'block';
    } else if (tag === 'summaries') {
        summaries.forEach(i => i.style.display = 'block');
        if(xraysSec) xraysSec.style.display = 'none';
    } else if (tag === 'xrays') {
        summaries.forEach(i => i.style.display = 'none');
        if(xraysSec) xraysSec.style.display = 'block';
    }
}

// Render dynamic patient bookings list
function renderPatientAppointments() {
    const container = document.getElementById('p-appointments-queue');
    if (!container) return;

    container.innerHTML = '';
    
    if (patientAppointments.length === 0) {
        container.innerHTML = '<div style="text-align:center; font-size:11px; padding:20px; color:#64748B;">No upcoming appointments.</div>';
        return;
    }

    patientAppointments.forEach(apt => {
        const card = document.createElement('div');
        card.className = 'apt-card';
        if (apt.date === "Oct 23, 2023") {
            card.innerHTML = `
                <div class="apt-title-row">
                    <span>${apt.treatment}</span>
                    <span class="apt-badge">${apt.status.toUpperCase()}</span>
                </div>
                <div class="apt-details">
                    <div style="color: var(--slate-medium); margin-bottom: 2px;">👨‍⚕️ ${apt.doctor}</div>
                    <div style="font-weight: 600; color: var(--slate-dark); display: flex; gap: 16px;">
                        <span>📅 ${apt.date}</span>
                        <span>⏰ ${apt.time}</span>
                    </div>
                </div>
                <div class="apt-actions">
                    <button class="btn-apt-sm" onclick="showPatientToast('Added to local System Calendar!')">Add to Calendar</button>
                    <button class="btn-sec" onclick="rescheduleAppointment('${apt.id}')" style="font-size: 9px; padding: 4px 10px;">Reschedule</button>
                </div>
            `;
        } else {
            card.innerHTML = `
                <div class="apt-title-row">
                    <span>${apt.treatment}</span>
                </div>
                <div class="apt-details">
                    <div style="color: var(--slate-medium); margin-bottom: 2px;">👨‍⚕️ ${apt.doctor}</div>
                    <div style="font-weight: 600; color: var(--slate-dark); display: flex; gap: 16px; margin-bottom: 8px;">
                        <span>📅 ${apt.date}</span>
                        <span>⏰ ${apt.time}</span>
                    </div>
                </div>
                <div style="display:flex; justify-content:flex-end;">
                    <button class="btn-apt-sm cancel" onclick="cancelAppointment('${apt.id}')">🚫 Cancel</button>
                </div>
            `;
        }
        container.appendChild(card);
    });
}

function openRescheduleModal() {
    if(patientAppointments.length > 0) {
        rescheduleAppointment(patientAppointments[0].id);
    }
}

function rescheduleAppointment(aptId) {
    const aptIndex = patientAppointments.findIndex(a => a.id === aptId);
    if(aptIndex !== -1) {
        patientAppointments[aptIndex].date = "Oct 24, 2023";
        patientAppointments[aptIndex].time = "10:30 AM";
        patientAppointments[aptIndex].status = "rescheduled";
        
        renderPatientAppointments();
        updatePatientDashboardCard(patientAppointments[aptIndex]);
        showPatientToast("Rescheduled to Oct 24, 2023!");
    }
}

function cancelAppointment(aptId) {
    if(confirm("Cancel this appointment booking?")) {
        patientAppointments = patientAppointments.filter(a => a.id !== aptId);
        renderPatientAppointments();
        updatePatientDashboardCard(null);
        showPatientToast("Appointment cancelled.", true);
    }
}

function updatePatientDashboardCard(apt) {
    const container = document.getElementById('p-dashboard-visit-card');
    if (!container) return;

    if (!apt) {
        container.innerHTML = `
            <div class="card-badge" style="background:var(--danger-red-tint); color:var(--danger-red)">NO UPCOMING VISITS</div>
            <p style="font-size:11px; color:var(--slate-medium); margin-top:8px; margin-bottom:12px;">Keep your teeth clean by booking a checkup.</p>
            <button class="btn-pri" style="width:100%" onclick="switchPatientTab('appointments')">Book Consult</button>
        `;
        return;
    }

    container.innerHTML = `
        <div class="card-badge">${apt.status.toUpperCase()}</div>
        <div class="visit-time-box">
            <h3>${apt.date}</h3>
            <span>${apt.time} - 10:15 AM</span>
        </div>
        <div class="visit-doc-info">
            <div class="doc-icon"><span class="avatar-icon">👩‍⚕️</span></div>
            <div class="doc-text">
                <h5>${apt.doctor}</h5>
                <p>${apt.treatment} • ${apt.clinic}</p>
            </div>
        </div>
        <div class="card-actions">
            <button class="btn-pri" onclick="showPatientToast('Verification code: DG-00439')">Details</button>
            <button class="btn-sec" onclick="rescheduleAppointment('${apt.id}')">Reschedule</button>
        </div>
    `;
}

function showPatientToast(message, isAlert = false) {
    const toast = document.getElementById('patient-toast');
    if (!toast) return;

    toast.innerText = message;
    if(isAlert) {
        toast.style.background = 'var(--danger-red)';
    } else {
        toast.style.background = 'var(--primary-blue)';
    }
    
    toast.classList.add('active');
    setTimeout(() => {
        toast.classList.remove('active');
    }, 3500);
}

// 4. DENTIST MOBILE PORTAL ROUTING
function switchDentistTab(tabName) {
    document.querySelectorAll('.dentist-screen').forEach(screen => {
        screen.classList.remove('active');
    });
    
    const targetScreen = document.getElementById(`d-screen-${tabName}`);
    if (targetScreen) {
        targetScreen.classList.add('active');
    }

    document.querySelectorAll('.dentist-footer .footer-nav-item').forEach(item => {
        item.classList.remove('active');
    });
    const activeIcon = document.querySelector(`[data-dtab-trigger="${tabName}"]`);
    if(activeIcon) activeIcon.classList.add('active');

    const footerNav = document.querySelector('.dentist-footer');
    if (footerNav) {
        footerNav.style.display = (tabName === 'auth') ? 'none' : 'flex';
    }

    if (tabName === 'patients') {
        renderDentistPatients();
    }
}

// Click timeline row patient -> navigate & search
function clickTimelinePatient(name) {
    switchDentistTab('patients');
    const search = document.getElementById('dentist-patient-search');
    if (search) {
        search.value = name;
        filterDentistPatients();
    }
}

// Click dentist search triggers redirect
function clickDentistSearch(input) {
    if(input.value.length > 2) {
        const val = input.value;
        switchDentistTab('patients');
        const search = document.getElementById('dentist-patient-search');
        if (search) {
            search.value = val;
            filterDentistPatients();
        }
        input.value = '';
    }
}

// Counter card routing
function clickDentistCounter(filterType) {
    switchDentistTab('patients');
    setDentistPatientTag(filterType);
}

// Patients Search Filter Tag
function setDentistPatientTag(tag) {
    currentDentistPatientTag = tag;
    document.querySelectorAll('#d-screen-patients .filter-tag').forEach(t => t.classList.remove('active'));
    
    // Highlight
    let searchId = `dtag-${tag}`;
    const activeTagBtn = document.getElementById(searchId);
    if(activeTagBtn) activeTagBtn.classList.add('active');

    renderDentistPatients();
}

function renderDentistPatients() {
    const container = document.getElementById('dentist-patient-list-container');
    if (!container) return;

    container.innerHTML = '';
    const query = document.getElementById('dentist-patient-search').value.toLowerCase();

    let filtered = dentistPatients.filter(pt => {
        const matchesQuery = pt.name.toLowerCase().includes(query) || pt.procedure.toLowerCase().includes(query);
        const matchesTag = (currentDentistPatientTag === 'all') || (pt.status === currentDentistPatientTag);
        return matchesQuery && matchesTag;
    });

    if (filtered.length === 0) {
        container.innerHTML = '<div style="text-align:center; font-size:11px; padding:20px; color:#64748B;">No patients match criteria.</div>';
        return;
    }

    filtered.forEach(pt => {
        const row = document.createElement('div');
        row.className = 'dentist-patient-row';
        row.innerHTML = `
            <div class="row-left" style="display:flex; gap:10px; align-items:center;">
                <div class="header-avatar-circle" style="width:34px; height:34px; font-size:11px;">${pt.initials}</div>
                <div style="display:flex; flex-direction:column;">
                    <h5>${pt.name}</h5>
                    <span class="patient-details-row">${pt.age} years • ${pt.gender}</span>
                    <span style="font-size:9px; color:var(--slate-light); margin-top:2px;">Last Visit: ${pt.lastVisit}</span>
                </div>
            </div>
            <div class="row-right">
                <span class="status ${pt.status}">${pt.status.toUpperCase()}</span>
                <span class="treatment">${pt.procedure}</span>
            </div>
        `;
        container.appendChild(row);
    });
}

function filterDentistPatients() {
    renderDentistPatients();
}

// Add new patient (CRUD)
function addNewDentistPatient() {
    const name = prompt("Enter Patient Name:");
    if (!name) return;
    const age = prompt("Enter Patient Age:", "30");
    if (!age) return;
    const gender = prompt("Enter Patient Gender (Male/Female):", "Female");
    if (!gender) return;
    const procedure = prompt("Enter Planned Procedure:", "Dental Checkup");
    if (!procedure) return;

    const initials = name.split(' ').map(n => n[0]).join('').toUpperCase().substring(0, 2);
    const newPt = {
        id: `DG-${Math.floor(100 + Math.random() * 900)}`,
        initials: initials,
        name: name,
        age: parseInt(age) || 30,
        gender: gender,
        status: "new",
        procedure: procedure,
        lastVisit: "Pending"
    };

    dentistPatients.unshift(newPt);
    renderDentistPatients();
    showDentistToast(`Successfully added ${name}!`);
}

function showDentistToast(message) {
    const toast = document.getElementById('dentist-toast');
    if (!toast) return;

    toast.innerText = message;
    toast.style.background = 'var(--success-green)';
    toast.classList.add('active');
    setTimeout(() => {
        toast.classList.remove('active');
    }, 3500);
}

let isAdminLoggedIn = false;

// 5. SUPER ADMIN DESKTOP ROUTING
function switchAdminView(viewName) {
    if (!isAdminLoggedIn) {
        showAdminToast("Please sign in to access Super Admin Desk.");
        logoutAdminUser();
        return;
    }

    // Hide all sub-views
    document.querySelectorAll('.admin-pane-view').forEach(view => {
        view.classList.remove('active');
    });
    
    // Show active sub-view
    const activeView = document.getElementById(`admin-view-${viewName}`);
    if(activeView) {
        activeView.classList.add('active');
    }

    // Toggle active link highlights
    document.querySelectorAll('.sidebar-link').forEach(link => {
        link.classList.remove('active');
    });
    const activeLink = document.querySelector(`.sidebar-link[data-aview="${viewName}"]`);
    if(activeLink) activeLink.classList.add('active');

    // Tab hooks
    if (viewName === 'inquiries') {
        renderAdminInquiries();
    }
}

function loginAdminUser() {
    const emailInput = document.getElementById('admin-login-email');
    const email = emailInput ? emailInput.value : "";
    if (!email) {
        showAdminToast("Please enter an administrator email.");
        return;
    }
    isAdminLoggedIn = true;

    // Hide standalone login page, show admin console layout
    const authPage = document.getElementById('admin-auth-standalone-page');
    const consoleLayout = document.getElementById('admin-main-console-layout');
    if (authPage) authPage.style.display = 'none';
    if (consoleLayout) consoleLayout.style.display = 'grid';

    showAdminToast("Master Control Console Authenticated ✓");
    switchAdminView('dashboard');
}

function logoutAdminUser() {
    isAdminLoggedIn = false;

    // Show standalone login page, hide admin console layout
    const authPage = document.getElementById('admin-auth-standalone-page');
    const consoleLayout = document.getElementById('admin-main-console-layout');
    if (authPage) authPage.style.display = 'flex';
    if (consoleLayout) consoleLayout.style.display = 'none';

    showAdminToast("Super Admin Logged Out Successfully.");
}

// Save settings configuration toast
function saveAdminSettings() {
    showAdminToast("Platform Configurations Saved Successfully!");
}

function showAdminToast(message) {
    const toast = document.getElementById('admin-toast');
    if(!toast) return;

    toast.innerText = message;
    toast.style.background = 'var(--primary-blue)';
    toast.style.top = '10px';
    
    setTimeout(() => {
        toast.style.top = '-50px';
    }, 3500);
}

// ==========================================================================
// 5.5 SUPPORT INQUIRIES & WHATSAPP REFERRAL LOGIC
// ==========================================================================
let submittedProblems = [
    {
        id: 1,
        patientName: "Emma Johnson",
        phone: "+12025550123",
        problem: "Severe wisdom tooth pain in upper left molar",
        status: "pending",
        doctor: "Dr. Robert Chen"
    },
    {
        id: 2,
        patientName: "David Kim",
        phone: "+12025550177",
        problem: "Braces alignment adjustment consultation needed",
        status: "pending",
        doctor: "Dr. Sarah Jenkins"
    }
];

let activeWhatsAppIndex = null;

function renderAdminInquiries() {
    const tbody = document.getElementById('admin-inquiries-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';
    
    // Update counter badge
    const pendingCount = submittedProblems.filter(p => p.status === 'pending').length;
    const badge = document.getElementById('admin-inquiry-counter-badge');
    if (badge) {
        badge.innerText = pendingCount;
        badge.style.display = pendingCount > 0 ? 'inline-block' : 'none';
    }

    if (submittedProblems.length === 0) {
        tbody.innerHTML = `<tr><td colspan="5" style="text-align:center; color:#64748B; font-size:12px; padding:20px;">No patient inquiries available.</td></tr>`;
        return;
    }

    submittedProblems.forEach((item, index) => {
        const badgeClass = item.status === 'pending' ? 'pending' : 'active';
        const row = document.createElement('tr');
        row.innerHTML = `
            <td><strong>${item.patientName}</strong><br><small style="color:var(--slate-medium);">${item.phone}</small></td>
            <td style="max-width:300px; white-space:normal; font-style:italic;">"${item.problem}"</td>
            <td>
                <select id="select-doc-${index}" class="table-search" style="padding:4px 8px; font-size:11px; background:white;" onchange="updateRecommendedDoctor(${index}, this.value)">
                    <option value="Dr. Clara Rodriguez" ${item.doctor === 'Dr. Clara Rodriguez' ? 'selected' : ''}>Dr. Clara Rodriguez (General)</option>
                    <option value="Dr. Sarah Jenkins" ${item.doctor === 'Dr. Sarah Jenkins' ? 'selected' : ''}>Dr. Sarah Jenkins (Orthodontics)</option>
                    <option value="Dr. Michael Chen" ${item.doctor === 'Dr. Michael Chen' ? 'selected' : ''}>Dr. Michael Chen (Periodontist)</option>
                    <option value="Dr. Robert Chen" ${item.doctor === 'Dr. Robert Chen' ? 'selected' : ''}>Dr. Robert Chen (Oral Surgeon)</option>
                </select>
            </td>
            <td><span class="status-badge ${badgeClass}">${item.status === 'pending' ? 'Pending' : 'Suggested'}</span></td>
            <td>
                <button class="btn-pri" style="background:#25D366; font-size:10px; padding:6px 12px; border:none; display:inline-flex; align-items:center; gap:4px; cursor:pointer;" onclick="dispatchWhatsAppInquiry(${index})">
                    💬 Suggest via WA
                </button>
            </td>
        `;
        tbody.appendChild(row);
    });
}
let registeredAdminPatients = [
    { name: "Jane Smith", age: 28, phone: "+1 202 555 0132", lastVisit: "Oct 12, 2023", status: "Active", avatar: "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=80" },
    { name: "Michael Ross", age: 45, phone: "+1 202 555 0187", lastVisit: "Sep 28, 2023", status: "Follow-up", avatar: "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=80" },
    { name: "Alice Wong", age: 32, phone: "+1 202 555 0156", lastVisit: "Aug 15, 2023", status: "Active", avatar: "https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=80" }
];

let registeredAdminDentists = [
    { name: "Dr. Clara Rodriguez", specialty: "General Dentistry", clinic: "Denta Care Clinic Wing A", exp: "12 Years Exp", status: "Verified", avatar: "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?auto=format&fit=crop&q=80&w=120" },
    { name: "Dr. Sarah Jenkins", specialty: "Orthodontics", clinic: "Apex Orthodontics", exp: "9 Years Exp", status: "Verified", avatar: "https://images.unsplash.com/photo-1594824813566-88855ce78907?auto=format&fit=crop&q=80&w=120" },
    { name: "Dr. Michael Chen", specialty: "Periodontist", clinic: "Smile Craft Dental Care", exp: "7 Years Exp", status: "Verified", avatar: "https://images.unsplash.com/photo-1622253692010-333f2da6031d?auto=format&fit=crop&q=80&w=120" }
];

function renderAdminPatientsTable() {
    const tbody = document.getElementById('admin-patients-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    registeredAdminPatients.forEach(pt => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td class="td-name-col">
                <div style="display:inline-flex; align-items:center; gap:8px;">
                    <img src="${pt.avatar}" style="width:24px; height:24px; border-radius:50%; object-fit:cover;">
                    <strong>${pt.name}</strong>
                </div>
            </td>
            <td>${pt.age}</td>
            <td>${pt.phone}</td>
            <td>${pt.lastVisit || 'Today (New User)'}</td>
            <td><span class="status-badge active">${pt.status || 'Active'}</span></td>
        `;
        tbody.appendChild(tr);
    });

    // Update Dashboard Patient Metric Counter
    const ptMetricsCard = document.querySelector('.metrics-row .metric-card:nth-child(1) h3');
    if (ptMetricsCard) {
        ptMetricsCard.innerText = registeredAdminPatients.length.toLocaleString();
    }
}

function renderAdminDentistsTable() {
    const tbody = document.getElementById('admin-dentists-tbody');
    if (!tbody) return;
    tbody.innerHTML = '';

    registeredAdminDentists.forEach(doc => {
        const tr = document.createElement('tr');
        tr.innerHTML = `
            <td class="td-name-col">
                <div style="display:inline-flex; align-items:center; gap:8px;">
                    <img src="${doc.avatar}" style="width:24px; height:24px; border-radius:50%; object-fit:cover;">
                    <strong>${doc.name}</strong>
                </div>
            </td>
            <td>${doc.specialty}</td>
            <td>${doc.clinic}</td>
            <td>${doc.exp || '5 Years Exp'}</td>
            <td><span class="status-badge active">${doc.status || 'Verified'}</span></td>
        `;
        tbody.appendChild(tr);
    });
}

function updateRecommendedDoctor(index, value) {
    if (submittedProblems[index]) {
        submittedProblems[index].doctor = value;
    }
}

function submitPatientProblem() {
    const textarea = document.getElementById('patient-problem-input');
    if (!textarea || !textarea.value.trim()) {
        showPatientToast('Please enter your problem description first.');
        return;
    }
    
    const newInquiry = {
        id: Date.now(),
        patientName: "Sarah Jenkins", 
        phone: "+12025550132",
        problem: textarea.value.trim(),
        status: "pending",
        doctor: "Dr. Clara Rodriguez"
    };

    submittedProblems.unshift(newInquiry);
    textarea.value = '';
    
    // Update counter badge immediately
    const badge = document.getElementById('admin-inquiry-counter-badge');
    if (badge) {
        const pendingCount = submittedProblems.filter(p => p.status === 'pending').length;
        badge.innerText = pendingCount;
        badge.style.display = 'inline-block';
    }

    showPatientToast("Problem submitted to Support Dispatcher!");
    
    // Re-render table if open
    renderAdminInquiries();
}

function dispatchWhatsAppInquiry(index) {
    const inquiry = submittedProblems[index];
    if (!inquiry) return;
    
    activeWhatsAppIndex = index;
    
    // Construct the WhatsApp message text
    const message = `Hello ${inquiry.patientName}, regarding your dental problem: "${inquiry.problem}", we recommend consulting with our specialist ${inquiry.doctor} at Denta Guru. You can book an appointment here: https://dentaguru-simulator.vercel.app/`;
    
    // Load data into simulated modal
    document.getElementById('wa-modal-phone').innerText = inquiry.phone;
    document.getElementById('wa-modal-title').innerText = `Referral Dispatcher: ${inquiry.patientName}`;
    document.getElementById('wa-modal-message').innerText = message;
    
    // Display Modal
    document.getElementById('whatsapp-modal').classList.add('active');
}

function closeWhatsAppModal() {
    document.getElementById('whatsapp-modal').classList.remove('active');
}

let activeReferralInquiry = null;

function openRealWhatsApp() {
    if (activeWhatsAppIndex === null) return;
    const inquiry = submittedProblems[activeWhatsAppIndex];
    if (!inquiry) return;
    
    // Mark status as Suggested
    inquiry.status = 'suggested';
    renderAdminInquiries();
    
    // Build real wa.me link
    const text = encodeURIComponent(`Hello ${inquiry.patientName}, regarding your dental problem: "${inquiry.problem}", we recommend consulting with our specialist ${inquiry.doctor} at Denta Guru. Book here: https://dentaguru-simulator.vercel.app/`);
    const cleanPhone = inquiry.phone.replace(/[^0-9]/g, '');
    const waUrl = `https://api.whatsapp.com/send?phone=${cleanPhone}&text=${text}`;
    
    closeWhatsAppModal();
    window.open(waUrl, '_blank');

    // Trigger WhatsApp Push Notification banner on Patient Phone Simulator
    setTimeout(() => {
        triggerPatientAppNotification(inquiry);
    }, 1000);
}

function triggerPatientAppNotification(inquiry) {
    activeReferralInquiry = inquiry;
    const banner = document.getElementById('simulated-notification');
    const notiText = document.getElementById('noti-text');
    if (notiText) {
        notiText.innerText = `Denta Guru recommended ${inquiry.doctor} for your inquiry. Tap to Book!`;
    }
    if (banner) {
        banner.style.display = 'flex';
        // Auto-hide after 8 seconds if ignored
        setTimeout(() => {
            if (banner) banner.style.display = 'none';
        }, 8000);
    }
}

function clickNotificationBanner() {
    const banner = document.getElementById('simulated-notification');
    if (banner) banner.style.display = 'none';

    if (!activeReferralInquiry) return;

    // Populate Referral Dialog Modal
    const initials = activeReferralInquiry.doctor.split(' ').map(n => n[0]).join('').substring(0, 2);
    const avatar = document.getElementById('ref-doc-avatar');
    const docName = document.getElementById('ref-doc-name');
    const docSpec = document.getElementById('ref-doc-spec');
    const desc = document.getElementById('referral-modal-desc');

    if (avatar) avatar.innerText = initials;
    if (docName) docName.innerText = activeReferralInquiry.doctor;
    if (docSpec) docSpec.innerText = "Recommended Specialist";
    if (desc) desc.innerText = `Denta Guru Support suggested ${activeReferralInquiry.doctor} for your problem: "${activeReferralInquiry.problem}".`;

    const refModal = document.getElementById('referral-modal');
    if (refModal) refModal.style.display = 'flex';
}

function closeReferralModal() {
    const refModal = document.getElementById('referral-modal');
    if (refModal) refModal.style.display = 'none';
}

function acceptReferralBooking() {
    if (!activeReferralInquiry) return;
    
    const newApt = {
        id: `APT-${Math.floor(200 + Math.random() * 800)}`,
        doctor: activeReferralInquiry.doctor,
        clinic: "Apex Orthodontics & Implants",
        date: "Oct 24, 2023",
        time: "09:30 AM",
        treatment: "Specialist Consultation",
        status: "confirmed"
    };

    patientAppointments.unshift(newApt);
    updatePatientDashboardCard(newApt);
    renderPatientAppointments();
    
    closeReferralModal();
    showPatientToast(`Booking Confirmed with ${activeReferralInquiry.doctor}!`);
    switchPatientTab('dashboard');
}

function updateRegAvatarPreview(url) {
    const preview = document.getElementById('reg-avatar-preview-img');
    if (preview) preview.src = url;
}

function setHeaderAvatar(avatarUrl) {
    const img = document.getElementById('patient-header-avatar-img');
    const icon = document.getElementById('patient-header-avatar-icon');
    if (avatarUrl) {
        if (img) {
            img.src = avatarUrl;
            img.style.display = 'block';
        }
        if (icon) icon.style.display = 'none';
    } else {
        if (img) img.style.display = 'none';
        if (icon) icon.style.display = 'inline';
    }
}

function updatePatientDashboardCard(appointment) {
    const emptyCard = document.getElementById('p-dashboard-empty-visit');
    const visitCard = document.getElementById('p-dashboard-visit-card');
    
    if (!appointment) {
        if (emptyCard) emptyCard.style.display = 'block';
        if (visitCard) visitCard.style.display = 'none';
        return;
    }

    if (emptyCard) emptyCard.style.display = 'none';
    if (visitCard) visitCard.style.display = 'block';

    const timeBoxH3 = visitCard.querySelector('.visit-time-box h3');
    const timeBoxSpan = visitCard.querySelector('.visit-time-box span');
    const docH5 = visitCard.querySelector('.doc-text h5');
    const docP = visitCard.querySelector('.doc-text p');

    if (timeBoxH3) timeBoxH3.innerText = appointment.date || "Oct 24, 2023";
    if (timeBoxSpan) timeBoxSpan.innerText = appointment.time || "09:30 AM - 10:15 AM";
    if (docH5) docH5.innerText = appointment.doctor || "Dr. Clara Rodriguez";
    if (docP) docP.innerText = appointment.treatment || "Dental Consultation";
}

function resetRegistrationForm() {
    uploadedGalleryDataUrl = null;
    const nameInput = document.getElementById('p-reg-name');
    if (nameInput) nameInput.value = "";
    
    const phoneInput = document.getElementById('p-reg-phone');
    if (phoneInput) phoneInput.value = "";
    
    const emailInput = document.getElementById('p-reg-email');
    if (emailInput) emailInput.value = "";
    
    const passInput = document.getElementById('p-reg-pass');
    if (passInput) passInput.value = "";

    const ageInput = document.getElementById('p-reg-age');
    if (ageInput) ageInput.value = "";

    const galleryInput = document.getElementById('p-reg-gallery-input');
    if (galleryInput) galleryInput.value = "";

    const previewImg = document.getElementById('reg-avatar-preview-img');
    const previewIcon = document.getElementById('reg-avatar-preview-icon');
    if (previewImg) {
        previewImg.src = "";
        previewImg.style.display = 'none';
    }
    if (previewIcon) previewIcon.style.display = 'inline';

    const btnLabel = document.getElementById('gallery-btn-label');
    if (btnLabel) btnLabel.innerText = "Choose from Gallery";
}

function setPatientPortalViewIsolation(isPatientLoggedIn) {
    const dentistBtn = document.querySelector('.portal-nav-btn[data-view="dentist"]');
    const adminBtn = document.querySelector('.portal-nav-btn[data-view="admin"]');
    
    if (isPatientLoggedIn) {
        if (dentistBtn) dentistBtn.style.display = 'none';
        if (adminBtn) adminBtn.style.display = 'none';
    } else {
        if (dentistBtn) dentistBtn.style.display = 'inline-block';
        if (adminBtn) adminBtn.style.display = 'inline-block';
    }
}

function logoutPatientUser() {
    setHeaderAvatar(null);
    resetRegistrationForm();
    updatePatientDashboardCard(null);
    setPatientPortalViewIsolation(false);
    showPatientToast("Logged out successfully.");
    switchPatientTab('auth');
}

function togglePatientAuthMode(mode) {
    const loginForm = document.getElementById('p-auth-login-form');
    const regForm = document.getElementById('p-auth-register-form');
    const tabLogin = document.getElementById('p-auth-tab-login');
    const tabReg = document.getElementById('p-auth-tab-register');

    if (mode === 'login') {
        if (loginForm) loginForm.style.display = 'flex';
        if (regForm) regForm.style.display = 'none';
        if (tabLogin) {
            tabLogin.className = 'btn-pri';
            tabLogin.style.background = 'var(--primary-blue)';
            tabLogin.style.color = 'white';
        }
        if (tabReg) {
            tabReg.className = 'btn-sec';
            tabReg.style.background = 'transparent';
            tabReg.style.color = 'var(--slate-medium)';
        }
    } else {
        if (loginForm) loginForm.style.display = 'none';
        if (regForm) regForm.style.display = 'flex';
        if (tabReg) {
            tabReg.className = 'btn-pri';
            tabReg.style.background = 'var(--primary-blue)';
            tabReg.style.color = 'white';
        }
        if (tabLogin) {
            tabLogin.className = 'btn-sec';
            tabLogin.style.background = 'transparent';
            tabLogin.style.color = 'var(--slate-medium)';
        }
    }
}

function triggerForgotPassword() {
    const emailInput = document.getElementById('p-login-email');
    const email = (emailInput && emailInput.value.trim()) ? emailInput.value.trim() : "sarah.jenkins@gmail.com";
    showPatientToast(`Password reset link sent to ${email}`);
}

function loginWithGoogle() {
    const googleAvatar = "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=120";
    setHeaderAvatar(googleAvatar);
    
    const profileImg = document.querySelector('.profile-avatar-img');
    if (profileImg) profileImg.src = googleAvatar;

    const profileName = document.querySelector('.profile-meta h3');
    if (profileName) profileName.innerText = "Sarah Jenkins";

    updatePatientDashboardCard(null);
    setPatientPortalViewIsolation(true);
    showPatientToast("Signed in via Google OAuth ✓");
    switchPatientTab('dashboard');
}

function loginPatientUser() {
    const emailInput = document.getElementById('p-login-email');
    const email = emailInput ? emailInput.value : "";
    if (!email) {
        showPatientToast("Please enter an email address.");
        return;
    }
    
    const rememberBox = document.getElementById('p-login-remember');
    if (rememberBox && rememberBox.checked) {
        showPatientToast(`Welcome back, Sarah! (Credentials remembered)`);
    } else {
        showPatientToast(`Welcome back, Sarah!`);
    }

    const defaultAvatar = "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=120";
    setHeaderAvatar(defaultAvatar);
    
    const profileImg = document.querySelector('.profile-avatar-img');
    if (profileImg) profileImg.src = defaultAvatar;

    updatePatientDashboardCard(null);
    setPatientPortalViewIsolation(true);
    switchPatientTab('dashboard');
}

let uploadedGalleryDataUrl = null;

function handleGalleryImageUpload(event) {
    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = function(e) {
        uploadedGalleryDataUrl = e.target.result;
        const previewImg = document.getElementById('reg-avatar-preview-img');
        const previewIcon = document.getElementById('reg-avatar-preview-icon');
        if (previewImg) {
            previewImg.src = uploadedGalleryDataUrl;
            previewImg.style.display = 'block';
        }
        if (previewIcon) previewIcon.style.display = 'none';

        const profileImg = document.querySelector('.profile-avatar-img');
        if (profileImg) profileImg.src = uploadedGalleryDataUrl;

        setHeaderAvatar(uploadedGalleryDataUrl);
        
        const btnLabel = document.getElementById('gallery-btn-label');
        if (btnLabel) btnLabel.innerText = "Photo Loaded ✓";
        showPatientToast("Profile photo updated from Gallery!");
    };
    reader.readAsDataURL(file);
}

function registerPatientUser() {
    const nameInput = document.getElementById('p-reg-name');
    const name = (nameInput && nameInput.value.trim()) ? nameInput.value.trim() : "Sarah Jenkins";
    
    const bloodSelect = document.getElementById('p-reg-bloodgroup');
    const bloodGroup = (bloodSelect && bloodSelect.value) ? bloodSelect.value : "O Positive";

    const ageInput = document.getElementById('p-reg-age');
    const age = (ageInput && ageInput.value.trim()) ? `${ageInput.value.trim()} Years` : "28 Years";

    const avatarUrl = uploadedGalleryDataUrl || "https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=120";

    setHeaderAvatar(avatarUrl);
    updatePatientDashboardCard(null);

    // Update Profile Screen avatar, name, blood group & age
    const profileImg = document.querySelector('.profile-avatar-img');
    if (profileImg) profileImg.src = avatarUrl;

    const profileName = document.querySelector('.profile-meta h3');
    if (profileName) profileName.innerText = name;

    const bgVal = document.getElementById('profile-bloodgroup-val');
    if (bgVal) bgVal.innerText = bloodGroup;

    const ageVal = document.getElementById('profile-age-val');
    if (ageVal) ageVal.innerText = age;

    const welcomeName = document.querySelector('.sub-welcome');
    if (welcomeName) welcomeName.innerText = `Hello, ${name.split(' ')[0]} 👋`;

    // Register Patient in Super Admin Patients table
    const phoneInput = document.getElementById('p-reg-phone');
    const phone = (phoneInput && phoneInput.value.trim()) ? phoneInput.value.trim() : "+1 202 555 0199";
    registeredAdminPatients.unshift({
        name: name,
        age: parseInt(age) || 28,
        phone: phone,
        lastVisit: "Registered Today",
        status: "Active",
        avatar: avatarUrl
    });
    renderAdminPatientsTable();

    showPatientToast(`Account created for ${name}!`);
    setPatientPortalViewIsolation(true);
    switchPatientTab('dashboard');
}

let isDentistLoggedIn = false;
let uploadedDentistGalleryDataUrl = null;

function handleDentistGalleryImageUpload(event) {
    const file = event.target.files[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = function(e) {
        uploadedDentistGalleryDataUrl = e.target.result;
        const previewImg = document.getElementById('d-reg-avatar-preview-img');
        const previewIcon = document.getElementById('d-reg-avatar-preview-icon');
        if (previewImg) {
            previewImg.src = uploadedDentistGalleryDataUrl;
            previewImg.style.display = 'block';
        }
        if (previewIcon) previewIcon.style.display = 'none';

        const btnLabel = document.getElementById('d-gallery-btn-label');
        if (btnLabel) btnLabel.innerText = "Photo Loaded ✓";
        showDentistToast("Practitioner photo loaded from Gallery!");
    };
    reader.readAsDataURL(file);
}

function openDentistAccountModal() {
    const modal = document.getElementById('dentist-account-modal');
    if (modal) modal.style.display = 'flex';
}

function closeDentistAccountModal() {
    const modal = document.getElementById('dentist-account-modal');
    if (modal) modal.style.display = 'none';
}

function clickDentistHeaderAvatar() {
    if (isDentistLoggedIn) {
        openDentistAccountModal();
    } else {
        showDentistToast("Please sign in to access Practitioner Console.");
        switchDentistTab('auth');
    }
}

function setDentistHeaderAvatar(avatarUrl) {
    const img = document.getElementById('dentist-header-avatar-img');
    const icon = document.getElementById('dentist-header-avatar-icon');
    const modalImg = document.getElementById('d-modal-avatar-img');
    
    if (avatarUrl) {
        if (img) {
            img.src = avatarUrl;
            img.style.display = 'block';
        }
        if (icon) icon.style.display = 'none';
        if (modalImg) modalImg.src = avatarUrl;
    } else {
        if (img) img.style.display = 'none';
        if (icon) icon.style.display = 'inline';
    }
}

function resetDentistRegistrationForm() {
    uploadedDentistGalleryDataUrl = null;
    const nameInput = document.getElementById('d-reg-name');
    if (nameInput) nameInput.value = "";
    
    const specInput = document.getElementById('d-reg-spec');
    if (specInput) specInput.value = "";

    const emailInput = document.getElementById('d-reg-email');
    if (emailInput) emailInput.value = "";

    const passInput = document.getElementById('d-reg-pass');
    if (passInput) passInput.value = "";

    const galleryInput = document.getElementById('d-reg-gallery-input');
    if (galleryInput) galleryInput.value = "";

    const previewImg = document.getElementById('d-reg-avatar-preview-img');
    const previewIcon = document.getElementById('d-reg-avatar-preview-icon');
    if (previewImg) {
        previewImg.src = "";
        previewImg.style.display = 'none';
    }
    if (previewIcon) previewIcon.style.display = 'inline';

    const btnLabel = document.getElementById('d-gallery-btn-label');
    if (btnLabel) btnLabel.innerText = "Choose from Gallery";
}

function toggleDentistAuthMode(mode) {
    const loginForm = document.getElementById('d-auth-login-form');
    const regForm = document.getElementById('d-auth-register-form');
    const tabLogin = document.getElementById('d-auth-tab-login');
    const tabReg = document.getElementById('d-auth-tab-register');

    if (mode === 'login') {
        if (loginForm) loginForm.style.display = 'flex';
        if (regForm) regForm.style.display = 'none';
        if (tabLogin) {
            tabLogin.className = 'btn-pri';
            tabLogin.style.background = 'var(--primary-blue)';
            tabLogin.style.color = 'white';
        }
        if (tabReg) {
            tabReg.className = 'btn-sec';
            tabReg.style.background = 'transparent';
            tabReg.style.color = 'var(--slate-medium)';
        }
    } else {
        if (loginForm) loginForm.style.display = 'none';
        if (regForm) regForm.style.display = 'flex';
        if (tabReg) {
            tabReg.className = 'btn-pri';
            tabReg.style.background = 'var(--primary-blue)';
            tabReg.style.color = 'white';
        }
        if (tabLogin) {
            tabLogin.className = 'btn-sec';
            tabLogin.style.background = 'transparent';
            tabLogin.style.color = 'var(--slate-medium)';
        }
    }
}

function triggerDentistForgotPassword() {
    const emailInput = document.getElementById('d-login-email');
    const email = (emailInput && emailInput.value.trim()) ? emailInput.value.trim() : "dr.clara@dentaguru.com";
    showDentistToast(`Reset verification link sent to ${email}`);
}

function loginDentistWithGoogle() {
    isDentistLoggedIn = true;
    const docAvatar = "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?auto=format&fit=crop&q=80&w=120";
    setDentistHeaderAvatar(docAvatar);
    showDentistToast("Authenticated via Google Workspace ✓");
    switchDentistTab('dashboard');
}

function loginDentistUser() {
    const email = document.getElementById('d-login-email').value;
    if (!email) {
        showDentistToast("Please enter a practitioner email.");
        return;
    }
    isDentistLoggedIn = true;
    const docAvatar = "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?auto=format&fit=crop&q=80&w=120";
    setDentistHeaderAvatar(docAvatar);
    showDentistToast(`Practitioner signed in: ${email}`);
    switchDentistTab('dashboard');
}

function registerDentistUser() {
    const nameInput = document.getElementById('d-reg-name');
    const name = (nameInput && nameInput.value.trim()) ? nameInput.value.trim() : "Dr. Clara Rodriguez";

    const specInput = document.getElementById('d-reg-spec');
    const spec = (specInput && specInput.value.trim()) ? specInput.value.trim() : "Orthodontics & Implants";

    isDentistLoggedIn = true;
    const docAvatar = uploadedDentistGalleryDataUrl || "https://images.unsplash.com/photo-1559839734-2b71ea197ec2?auto=format&fit=crop&q=80&w=120";
    setDentistHeaderAvatar(docAvatar);

    const modalName = document.getElementById('d-modal-name');
    if (modalName) modalName.innerText = name;

    const modalSpec = document.getElementById('d-modal-spec');
    if (modalSpec) modalSpec.innerText = spec;

    const welcomeHeader = document.querySelector('.dentist-welcome h4');
    if (welcomeHeader) welcomeHeader.innerText = name;

    // Register Dentist in Super Admin Dentists table
    registeredAdminDentists.unshift({
        name: name,
        specialty: spec,
        clinic: `${name.split(' ')[1] || 'Specialist'} Dental Clinic`,
        exp: "New Registration",
        status: "Verified",
        avatar: docAvatar
    });
    renderAdminDentistsTable();

    showDentistToast(`Registered clinic workspace for ${name}!`);
    switchDentistTab('dashboard');
}

function logoutDentistUser() {
    isDentistLoggedIn = false;
    setDentistHeaderAvatar(null);
    resetDentistRegistrationForm();
    showDentistToast("Logged out of Clinical Console.");
    switchDentistTab('auth');
}

// 6. INITIAL RUNS
window.addEventListener('DOMContentLoaded', () => {
    renderPatientAppointments();
    renderDentistPatients();
    renderAdminInquiries();
    renderAdminPatientsTable();
    renderAdminDentistsTable();
});
