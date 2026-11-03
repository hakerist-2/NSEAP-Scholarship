import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../repositories/education_repository.dart';
import '../../../theme/nseap_theme.dart';
import '../../../utils/academic_year.dart';
import '../../../models/document_requirement.dart';
import '../../../services/realtime_sync.dart';
import '../../data/admin_repository.dart';
import '../../widgets/admin_widgets.dart';

/// Admin form for approved walk-in scholars.
/// Reuses the same fill-up form and required documents as the scholar flow.
/// Save creates an approved (scholar) record; Cancel discards.
class WalkInScholarFormPage extends StatefulWidget {
  const WalkInScholarFormPage({required this.repository, super.key});

  final AdminRepository repository;

  @override
  State<WalkInScholarFormPage> createState() => _WalkInScholarFormPageState();
}

class _WalkInScholarFormPageState extends State<WalkInScholarFormPage>
    with RealtimeSyncMixin {
  final _personalFormKey = GlobalKey<FormState>();
  final _guardianFormKey = GlobalKey<FormState>();
  final _educationRepository = EducationRepository();
  final _imagePicker = ImagePicker();

  final _firstNameController = TextEditingController();
  final _middleNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _dateOfBirthController = TextEditingController();
  final _emailController = TextEditingController();
  final _contactController = TextEditingController();
  final _addressController = TextEditingController();
  final _schoolController = TextEditingController();
  final _courseController = TextEditingController();
  final _studentIdController = TextEditingController();

  final _fatherNameController = TextEditingController();
  final _fatherOccupationController = TextEditingController();
  String? _selectedFatherIncome;
  final _motherNameController = TextEditingController();
  final _motherOccupationController = TextEditingController();
  String? _selectedMotherIncome;
  final _totalHouseholdIncomeController = TextEditingController();
  final _householdMembersController = TextEditingController();

  String? _selectedSex;
  String? _selectedYearLevel;
  School? _selectedSchool;
  Program? _selectedProgram;

  String _selectedAcademicYear = AcademicYearUtils.currentAcademicYear();
  String _selectedSemester = 'First Semester';

  int _currentStage = 0;
  bool _showValidationErrors = false;
  bool _isSaving = false;
  bool _isSearchingSchools = false;
  bool _isSearchingPrograms = false;

  List<StudentDocument> _requiredDocuments = [];
  bool _requirementsLoading = true;
  String? _requirementsError;

  @override
  Set<String> get realtimeTables => const {'document_requirements'};

  @override
  void initState() {
    super.initState();
    refreshRealtime();
  }

  @override
  Future<void> refreshRealtime() async {
    try {
      final requirements = await widget.repository.getDocumentRequirements(
        'scholar',
      );
      if (!mounted) return;
      setState(() {
        _requiredDocuments = DocumentRequirement.mergeDocuments(
          requirements,
          _requiredDocuments,
        );
        _requirementsLoading = false;
        _requirementsError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _requirementsLoading = false;
          _requirementsError = 'Unable to load scholar requirements.';
        });
      }
    }
  }

  static const _stageTitles = ['Personal', 'Parent/Guardian', 'Requirements'];
  static const _stageIcons = [
    Icons.person_outline,
    Icons.family_restroom_outlined,
    Icons.upload_file_outlined,
  ];

  bool get _allDocumentsSelected =>
      _requiredDocuments.every((d) => d.isSelected);

  void _goToStage(int stage) {
    if (stage < 0 || stage >= _stageTitles.length) return;
    setState(() => _currentStage = stage);
  }

  Future<void> _selectDocument(int index) async {
    final document = _requiredDocuments[index];
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg'],
      withData: true,
    );
    if (result == null || result.files.single.bytes == null || !mounted) {
      return;
    }
    final file = result.files.single;
    final ext = file.extension?.toLowerCase();
    final mimeType = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
        ? 'image/png'
        : 'image/jpeg';
    _setDocument(document, file.name, file.bytes!, mimeType);
  }

  Future<void> _takeDocumentPhoto(int index) async {
    final document = _requiredDocuments[index];
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      final ext = image.name.split('.').last.toLowerCase();
      _setDocument(
        document,
        image.name,
        bytes,
        ext == 'png' ? 'image/png' : 'image/jpeg',
      );
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) debugPrint('Camera error: $e');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open camera.')));
    }
  }

  void _setDocument(
    StudentDocument document,
    String fileName,
    List<int> bytes,
    String mime,
  ) {
    if (!_requiredDocuments.contains(document)) return;
    if (bytes.length > 5 * 1024 * 1024) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Each file must be 5 MB or smaller.')),
      );
      return;
    }
    setState(() {
      final d = document;
      d.isSelected = true;
      d.fileName = fileName;
      d.bytes = bytes;
      d.mimeType = mime;
    });
  }

  void _removeDocument(int index) {
    setState(() {
      final d = _requiredDocuments[index];
      d.isSelected = false;
      d.fileName = null;
      d.bytes = null;
      d.mimeType = null;
    });
  }

  Future<void> _save() async {
    if (_isSaving || _requirementsLoading) return;
    setState(() {
      _showValidationErrors = true;
      _isSaving = true;
    });
    await refreshRealtime();
    if (!mounted) return;
    if (_requirementsError != null) {
      setState(() => _isSaving = false);
      showAdminMessage(context, _requirementsError!, error: true);
      return;
    }

    final personalValid = _personalFormKey.currentState?.validate() ?? false;
    final guardianValid = _guardianFormKey.currentState?.validate() ?? false;
    final docsValid = _allDocumentsSelected;

    if (!personalValid || !guardianValid || !docsValid) {
      int firstIncomplete = 0;
      if (!personalValid) {
        firstIncomplete = 0;
      } else if (!guardianValid) {
        firstIncomplete = 1;
      } else {
        firstIncomplete = 2;
      }
      setState(() {
        _currentStage = firstIncomplete;
        _isSaving = false;
      });
      await _showMissingDialog(personalValid, guardianValid, docsValid);
      return;
    }

    if (_isSearchingSchools || _isSearchingPrograms) {
      setState(() => _isSaving = false);
      showAdminMessage(
        context,
        'Please wait for search to finish.',
        error: true,
      );
      return;
    }

    final payload = <String, dynamic>{
      'first_name': _firstNameController.text.trim(),
      'middle_name': _middleNameController.text.trim().isEmpty
          ? null
          : _middleNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'date_of_birth': _dateOfBirthController.text.trim(),
      'sex': _selectedSex,
      'email': _emailController.text.trim(),
      'contact_number': _contactController.text.trim(),
      'address': _addressController.text.trim(),
      'school': _schoolController.text.trim(),
      'course': _courseController.text.trim(),
      'year_level': _selectedYearLevel,
      'student_id_number': _studentIdController.text.trim(),
      'father_name': _fatherNameController.text.trim(),
      'father_occupation': _fatherOccupationController.text.trim(),
      'father_income_range': _selectedFatherIncome,
      'mother_name': _motherNameController.text.trim(),
      'mother_occupation': _motherOccupationController.text.trim(),
      'mother_income_range': _selectedMotherIncome,
      'household_monthly_income': _totalHouseholdIncomeController.text.trim(),
      'household_members': _householdMembersController.text.trim(),
      'applicant_type': 'existing_scholar',
      'academic_year': _selectedAcademicYear,
      'semester': _selectedSemester,
    };

    try {
      final ids = await widget.repository.createWalkInScholar(payload);
      // Upload documents
      for (final doc in _requiredDocuments) {
        if (doc.bytes == null || doc.fileName == null || doc.mimeType == null) {
          continue;
        }
        await widget.repository.uploadWalkInDocument(
          applicationId: ids.applicationId,
          userId: ids.userId,
          documentType: doc.type,
          fileName: doc.fileName!,
          bytes: doc.bytes!,
          mimeType: doc.mimeType!,
        );
      }
      if (!mounted) return;
      showAdminMessage(context, 'Walk-in scholar saved to Approved.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      showAdminMessage(context, readableAdminError(e), error: true);
      setState(() => _isSaving = false);
    }
  }

  Future<void> _showMissingDialog(
    bool personalValid,
    bool guardianValid,
    bool docsValid,
  ) {
    final missingDocs =
        _requiredDocuments.length -
        _requiredDocuments.where((d) => d.isSelected).length;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange,
          size: 42,
        ),
        title: const Text(
          'Incomplete Information',
          textAlign: TextAlign.center,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please review before saving:'),
            const SizedBox(height: 16),
            _validationRow('Personal Information', personalValid),
            const SizedBox(height: 10),
            _validationRow('Parent/Guardian Information', guardianValid),
            const SizedBox(height: 10),
            _validationRow(
              docsValid
                  ? _stageTitles[2]
                  : '${_stageTitles[2]} ($missingDocs missing)',
              docsValid,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Review'),
          ),
        ],
      ),
    );
  }

  Widget _validationRow(String title, bool complete) => Row(
    children: [
      Icon(
        complete ? Icons.check_circle : Icons.cancel,
        color: complete ? AppColors.success : Colors.red,
        size: 21,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            color: complete ? AppColors.success : Colors.red,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _dateOfBirthController.dispose();
    _emailController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _schoolController.dispose();
    _courseController.dispose();
    _studentIdController.dispose();
    _fatherNameController.dispose();
    _fatherOccupationController.dispose();
    _motherNameController.dispose();
    _motherOccupationController.dispose();
    _totalHouseholdIncomeController.dispose();
    _householdMembersController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF8FAFC),
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF0F172A),
      elevation: 0,
      title: const Text(
        'Add Walk-in Scholar',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.pop(context),
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              18,
              6,
              18,
              18 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopStageArea(),
                const SizedBox(height: 18),
                IndexedStack(
                  index: _currentStage,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildAcademicYearSemesterSelectors(),
                        const SizedBox(height: 16),
                        PersonalFormWidget(
                          formKey: _personalFormKey,
                          firstNameController: _firstNameController,
                          middleNameController: _middleNameController,
                          lastNameController: _lastNameController,
                          dateOfBirthController: _dateOfBirthController,
                          emailController: _emailController,
                          contactController: _contactController,
                          addressController: _addressController,
                          schoolController: _schoolController,
                          courseController: _courseController,
                          studentIdController: _studentIdController,
                          selectedSex: _selectedSex,
                          selectedYearLevel: _selectedYearLevel,
                          selectedSchool: _selectedSchool,
                          selectedProgram: _selectedProgram,
                          showValidationErrors: _showValidationErrors,
                          educationRepository: _educationRepository,
                          onSexChanged: (v) => setState(() => _selectedSex = v),
                          onYearLevelChanged: (v) =>
                              setState(() => _selectedYearLevel = v),
                          onSchoolSelected: (s) =>
                              setState(() => _selectedSchool = s),
                          onProgramSelected: (p) =>
                              setState(() => _selectedProgram = p),
                          onSchoolSearchChanged: (b) =>
                              setState(() => _isSearchingSchools = b),
                          onProgramSearchChanged: (b) =>
                              setState(() => _isSearchingPrograms = b),
                        ),
                      ],
                    ),
                    ParentFormWidget(
                      formKey: _guardianFormKey,
                      fatherNameController: _fatherNameController,
                      fatherOccupationController: _fatherOccupationController,
                      selectedFatherIncome: _selectedFatherIncome,
                      onFatherIncomeChanged: (v) =>
                          setState(() => _selectedFatherIncome = v),
                      motherNameController: _motherNameController,
                      motherOccupationController: _motherOccupationController,
                      selectedMotherIncome: _selectedMotherIncome,
                      onMotherIncomeChanged: (v) =>
                          setState(() => _selectedMotherIncome = v),
                      totalHouseholdIncomeController:
                          _totalHouseholdIncomeController,
                      householdMembersController: _householdMembersController,
                      showValidationErrors: _showValidationErrors,
                    ),
                    if (_requirementsLoading)
                      const Center(child: CircularProgressIndicator())
                    else if (_requirementsError != null)
                      Column(
                        children: [
                          Text(_requirementsError!),
                          TextButton(
                            onPressed: refreshRealtime,
                            child: const Text('Retry'),
                          ),
                        ],
                      )
                    else
                      RequirementsFormWidget(
                        documents: _requiredDocuments,
                        showValidationErrors: _showValidationErrors,
                        onSelectDocument: _selectDocument,
                        onTakePhoto: _takeDocumentPhoto,
                        onRemoveDocument: _removeDocument,
                        title: 'Scholar Requirements',
                        description:
                            'PDF, JPG or PNG · max 5 MB each. All listed documents are required.',
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildNavButtons(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _buildAcademicYearSemesterSelectors() {
    final years = AcademicYearUtils.generateAcademicYears();
    return NseapSurface(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Academic Period',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedAcademicYear,
            decoration: const InputDecoration(labelText: 'Academic Year'),
            items: years
                .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                .toList(),
            onChanged: (v) => setState(() => _selectedAcademicYear = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedSemester,
            decoration: const InputDecoration(labelText: 'Semester'),
            items: const [
              DropdownMenuItem(
                value: 'First Semester',
                child: Text('First Semester'),
              ),
              DropdownMenuItem(
                value: 'Second Semester',
                child: Text('Second Semester'),
              ),
            ],
            onChanged: (v) => setState(() => _selectedSemester = v!),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStageArea() {
    final progress = (_currentStage + 1) / _stageTitles.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: AppElevation.shadowXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  'Step ${_currentStage + 1} of ${_stageTitles.length}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${(progress * 100).round()}% complete',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _stageTitles[_currentStage],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            switch (_currentStage) {
              0 => 'Tell us about the scholar',
              1 => 'Family & household details',
              _ => 'Upload required documents',
            },
            style: const TextStyle(
              fontSize: 12.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.borderLight,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          _buildStageIndicator(),
        ],
      ),
    );
  }

  Widget _buildStageIndicator() => Stack(
    alignment: Alignment.topCenter,
    children: [
      Positioned(
        top: 22,
        left: 50,
        right: 50,
        child: Row(
          children: List.generate(_stageTitles.length - 1, (i) {
            final completed = _currentStage > i;
            return Expanded(
              child: Container(
                height: 3,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: completed
                      ? AppColors.primary
                      : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            );
          }),
        ),
      ),
      Row(
        children: List.generate(
          _stageTitles.length,
          (i) => Expanded(child: _buildStageItem(i)),
        ),
      ),
    ],
  );

  Widget _buildStageItem(int index) {
    final isCurrent = _currentStage == index;
    final isCompleted = _currentStage > index;
    Color circle = Colors.white;
    Color border = const Color(0xFFE2E8F0);
    Color icon = AppColors.textTertiary;
    if (isCompleted || isCurrent) {
      circle = AppColors.primary;
      border = AppColors.primary;
      icon = Colors.white;
    }
    return InkWell(
      onTap: () => _goToStage(index),
      borderRadius: BorderRadius.circular(14),
      child: Column(
        children: [
          Container(
            width: isCurrent ? 48 : 44,
            height: isCurrent ? 48 : 44,
            decoration: BoxDecoration(
              color: circle,
              shape: BoxShape.circle,
              border: Border.all(color: border, width: 2),
            ),
            child: Icon(
              isCompleted ? Icons.check_rounded : _stageIcons[index],
              color: icon,
              size: isCurrent ? 23 : 20,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stageTitles[index],
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isCurrent || isCompleted
                  ? AppColors.primary
                  : AppColors.textTertiary,
              fontSize: 11.5,
              fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavButtons() {
    final isLast = _currentStage == _stageTitles.length - 1;
    final isFirst = _currentStage == 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (!isFirst)
              Expanded(
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () => _goToStage(_currentStage - 1),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Previous'),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ),
            if (!isFirst) const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: isLast
                      ? _save
                      : () => _goToStage(_currentStage + 1),
                  icon: _isSaving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          isLast
                              ? Icons.save_outlined
                              : Icons.arrow_forward_rounded,
                          size: 18,
                        ),
                  label: Text(
                    _isSaving
                        ? 'Saving...'
                        : isLast
                        ? 'Save'
                        : 'Continue',
                  ),
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: OutlinedButton(
            onPressed: _isSaving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              side: const BorderSide(color: AppColors.borderLight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}
